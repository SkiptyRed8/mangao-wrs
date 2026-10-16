package com.mangao.wrs.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.Env;
import com.mangao.wrs.core.M;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import org.springframework.stereotype.Component;

/**
 * Push notifications to phones (step 36) with Firebase Cloud Messaging (HTTP v1 API).
 * Turned on when .env has FIREBASE_SERVICE_ACCOUNT=path\to\service-account.json
 * (Firebase console > Project settings > Service accounts > Generate new private key).
 * Without it, nothing is sent: the app still gets every alert in the app (bell and banner).
 */
@Component
public class Push {
  private final Db db;
  private final ObjectMapper json = new ObjectMapper();
  private final HttpClient http = HttpClient.newHttpClient();
  private final ScheduledExecutorService timer = Executors.newSingleThreadScheduledExecutor(r -> {
    Thread t = new Thread(r, "push");
    t.setDaemon(true);
    return t;
  });
  private Map<String, Object> creds; // null = not read yet
  private boolean off = false;
  private String accessToken = null;
  private long accessExp = 0;

  public Push(Db db) {
    this.db = db;
  }

  @SuppressWarnings("unchecked")
  private synchronized Map<String, Object> credentials() {
    if (creds != null || off) return creds;
    String file = Env.firebaseServiceAccount();
    if (file.isEmpty()) {
      off = true;
      return null;
    }
    try {
      Path p = Env.baseDir().resolve(file);
      creds = json.readValue(Files.readString(p), Map.class);
      System.out.println("[push] Firebase project " + creds.get("project_id") + ": push notifications on");
    } catch (Exception e) {
      System.err.println("[push] cannot read FIREBASE_SERVICE_ACCOUNT (" + e.getMessage() + "); push notifications off");
      off = true;
    }
    return creds;
  }

  public boolean enabled() {
    return credentials() != null;
  }

  private synchronized String token() throws Exception {
    long now = System.currentTimeMillis() / 1000;
    if (accessToken != null && accessExp - 60 > now) return accessToken;
    Map<String, Object> c = credentials();
    Base64.Encoder enc = Base64.getUrlEncoder().withoutPadding();
    String head = enc.encodeToString("{\"alg\":\"RS256\",\"typ\":\"JWT\"}".getBytes(StandardCharsets.UTF_8));
    String body = enc.encodeToString(json.writeValueAsBytes(M.of(
        "iss", c.get("client_email"),
        "scope", "https://www.googleapis.com/auth/firebase.messaging",
        "aud", "https://oauth2.googleapis.com/token",
        "iat", now,
        "exp", now + 3600)));
    Signature sig = Signature.getInstance("SHA256withRSA");
    sig.initSign(privateKey(String.valueOf(c.get("private_key"))));
    sig.update((head + "." + body).getBytes(StandardCharsets.UTF_8));
    String assertion = head + "." + body + "." + enc.encodeToString(sig.sign());
    HttpResponse<String> res = http.send(HttpRequest.newBuilder(URI.create("https://oauth2.googleapis.com/token"))
        .header("Content-Type", "application/x-www-form-urlencoded")
        .POST(HttpRequest.BodyPublishers.ofString("grant_type=" + URLEncoder.encode("urn:ietf:params:oauth:grant-type:jwt-bearer", StandardCharsets.UTF_8)
            + "&assertion=" + assertion))
        .build(), HttpResponse.BodyHandlers.ofString());
    if (res.statusCode() != 200) throw new IllegalStateException("token " + res.statusCode());
    @SuppressWarnings("unchecked")
    Map<String, Object> d = json.readValue(res.body(), Map.class);
    accessToken = String.valueOf(d.get("access_token"));
    accessExp = now + (d.get("expires_in") instanceof Number n ? n.longValue() : 3600);
    return accessToken;
  }

  private static PrivateKey privateKey(String pem) throws Exception {
    String b64 = pem.replace("-----BEGIN PRIVATE KEY-----", "").replace("-----END PRIVATE KEY-----", "").replaceAll("\\s", "");
    return KeyFactory.getInstance("RSA").generatePrivate(new PKCS8EncodedKeySpec(Base64.getDecoder().decode(b64)));
  }

  private void deliver(Long userId, String guestToken, String title, String message, String type, Long orderId) throws Exception {
    List<Map<String, Object>> rows = userId != null
        ? db.query("SELECT push_token FROM device_tokens WHERE user_id = ?", userId)
        : db.query("SELECT push_token FROM device_tokens WHERE guest_token = ?", guestToken);
    if (rows.isEmpty()) return;
    String token = token();
    Map<String, Object> c = credentials();
    for (Map<String, Object> r : rows) {
      String pushToken = String.valueOf(r.get("push_token"));
      String body = json.writeValueAsString(M.of("message", M.of(
          "token", pushToken,
          "notification", M.of("title", title, "body", message),
          "data", M.of("type", type == null ? "" : type, "orderId", orderId == null ? "" : String.valueOf(orderId)),
          "android", M.of("priority", "high"))));
      HttpResponse<String> res = http.send(HttpRequest.newBuilder(URI.create("https://fcm.googleapis.com/v1/projects/" + c.get("project_id") + "/messages:send"))
          .header("Authorization", "Bearer " + token)
          .header("Content-Type", "application/json")
          .POST(HttpRequest.BodyPublishers.ofString(body))
          .build(), HttpResponse.BodyHandlers.ofString());
      if (res.statusCode() == 404 || res.statusCode() == 400) {
        // The phone uninstalled the app or the token expired.
        db.update("DELETE FROM device_tokens WHERE push_token = ?", pushToken);
      }
    }
  }

  /** Sends a push to the phones of one account or guest. Never throws and never slows the request. */
  public void send(Long userId, String guestToken, String title, String message, String type, Long orderId) {
    if ((userId == null && guestToken == null) || !enabled()) return;
    timer.schedule(() -> {
      try {
        deliver(userId, guestToken, title, message, type, orderId);
      } catch (Exception e) {
        System.err.println("[push] " + e.getMessage());
      }
    }, 300, TimeUnit.MILLISECONDS);
  }
}
