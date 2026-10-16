package com.mangao.wrs.core;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * Small HS256 JSON Web Tokens (same format as the old server, so saved log-ins keep working).
 * Used for log-in tokens (30 days), the forgot-password reset token (15 minutes) and the export
 * download link (5 minutes).
 */
public final class Jwt {
  private static final ObjectMapper JSON = new ObjectMapper();
  private static final Base64.Encoder ENC = Base64.getUrlEncoder().withoutPadding();
  private static final Base64.Decoder DEC = Base64.getUrlDecoder();

  private Jwt() {}

  public static String sign(Map<String, Object> claims, long seconds) {
    try {
      long iat = System.currentTimeMillis() / 1000;
      Map<String, Object> payload = new LinkedHashMap<>(claims);
      payload.put("iat", iat);
      payload.put("exp", iat + seconds);
      String head = ENC.encodeToString("{\"alg\":\"HS256\",\"typ\":\"JWT\"}".getBytes(StandardCharsets.UTF_8));
      String body = ENC.encodeToString(JSON.writeValueAsBytes(payload));
      return head + "." + body + "." + ENC.encodeToString(hmac(head + "." + body));
    } catch (Exception e) {
      throw new IllegalStateException(e);
    }
  }

  /** The claims, or null when the token is wrong or expired. */
  @SuppressWarnings("unchecked")
  public static Map<String, Object> verify(String token) {
    try {
      if (token == null) return null;
      String[] p = token.split("\\.");
      if (p.length != 3) return null;
      byte[] expected = hmac(p[0] + "." + p[1]);
      if (!MessageDigest.isEqual(expected, DEC.decode(p[2]))) return null;
      Map<String, Object> head = JSON.readValue(DEC.decode(p[0]), Map.class);
      if (!"HS256".equals(head.get("alg"))) return null;
      Map<String, Object> claims = JSON.readValue(DEC.decode(p[1]), Map.class);
      Object exp = claims.get("exp");
      if (exp != null && V.num(exp) <= System.currentTimeMillis() / 1000.0) return null;
      return claims;
    } catch (Exception e) {
      return null;
    }
  }

  private static byte[] hmac(String data) throws Exception {
    Mac mac = Mac.getInstance("HmacSHA256");
    mac.init(new SecretKeySpec(Env.jwtSecret().getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
    return mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
  }
}
