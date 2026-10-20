package com.mangao.wrs.service;

import com.mangao.wrs.core.Env;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * Keeps the free online server awake. Render puts a free server to sleep after 15 minutes without
 * visitors, and the next person then waits about a minute. GitHub's scheduled visits come only every
 * few hours, so the server also visits its own public address (/health) every 10 minutes.
 * Render gives the address in RENDER_EXTERNAL_URL; on the laptop it is not set, so this does nothing.
 * KEEP_AWAKE=false turns it off.
 */
@Component
public class KeepAwake {
  private static final long EVERY_MINUTES = 10;
  private ScheduledExecutorService timer;

  @EventListener(ApplicationReadyEvent.class)
  public void start() {
    String base = Env.get("RENDER_EXTERNAL_URL", "").trim();
    if (base.isEmpty() || Env.testMode() || "false".equalsIgnoreCase(Env.get("KEEP_AWAKE", "true").trim())) return;
    while (base.endsWith("/")) base = base.substring(0, base.length() - 1);
    URI health = URI.create(base + "/health");
    HttpClient client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(20)).build();
    timer = Executors.newSingleThreadScheduledExecutor(r -> {
      Thread t = new Thread(r, "keep-awake");
      t.setDaemon(true);
      return t;
    });
    timer.scheduleAtFixedRate(() -> {
      try {
        HttpRequest req = HttpRequest.newBuilder(health).timeout(Duration.ofSeconds(60)).GET().build();
        client.send(req, HttpResponse.BodyHandlers.discarding());
      } catch (Exception e) {
        System.err.println("[keep-awake] " + e.getMessage());
      }
    }, EVERY_MINUTES, EVERY_MINUTES, TimeUnit.MINUTES);
    System.out.println("[keep-awake] visiting " + health + " every " + EVERY_MINUTES + " minutes");
  }
}
