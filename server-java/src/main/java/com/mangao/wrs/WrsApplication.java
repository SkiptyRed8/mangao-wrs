package com.mangao.wrs;

import com.mangao.wrs.core.Env;
import com.mangao.wrs.service.Migrate;
import com.mangao.wrs.service.SetupDb;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;

/**
 * Mangao WRS backend (Java + Spring Boot). Same REST API, port (3100), database and messages as the
 * first Node.js server, so the Flutter app works the same.
 *   java -jar mangao-wrs-server.jar                     start the server
 *   java -jar mangao-wrs-server.jar --setup-db [--demo] build the database (RESET-DEMO-DATA.bat)
 */
@SpringBootApplication
public class WrsApplication {
  private final Migrate migrate;

  public WrsApplication(Migrate migrate) {
    this.migrate = migrate;
  }

  public static void main(String[] args) throws Exception {
    Env.load(Path.of(System.getProperty("wrs.home", ".")));
    List<String> a = Arrays.asList(args);
    if (a.contains("--setup-db")) {
      try {
        SetupDb.run(a.contains("--demo"), Env.dbName(), false);
        System.exit(0);
      } catch (Exception e) {
        System.err.println("Database setup failed: " + e.getMessage());
        System.exit(1);
      }
    }
    SpringApplication app = new SpringApplication(WrsApplication.class);
    Map<String, Object> p = new HashMap<>();
    p.put("server.port", Env.port());
    p.put("spring.main.banner-mode", "off");
    p.put("spring.datasource.url", "jdbc:mysql://" + Env.dbHost() + ":" + Env.dbPort() + "/" + Env.dbName()
        + "?useUnicode=true&characterEncoding=utf8&tinyInt1isBit=false&allowPublicKeyRetrieval=true&useSSL=false"
        + "&connectionTimeZone=%2B08:00&forceConnectionTimeZoneToSession=true");
    p.put("spring.datasource.username", Env.dbUser());
    p.put("spring.datasource.password", Env.dbPassword());
    p.put("spring.datasource.hikari.maximum-pool-size", 10);
    p.put("spring.datasource.hikari.initialization-fail-timeout", -1);
    p.put("spring.datasource.hikari.connection-timeout", 5000);
    p.put("spring.sql.init.mode", "never");
    p.put("spring.mvc.throw-exception-if-no-handler-found", true);
    p.put("spring.web.resources.add-mappings", true);
    p.put("server.error.whitelabel.enabled", false);
    p.put("server.tomcat.max-swallow-size", "10MB");
    p.put("logging.level.root", "WARN");
    p.put("logging.level.com.mangao", "INFO");
    app.setDefaultProperties(p);
    app.run(args);
  }

  @EventListener(ApplicationReadyEvent.class)
  public void ready() {
    System.out.println("Mangao WRS API (Java) running on http://localhost:" + Env.port() + "  (health check: /health)");
    if (!Env.smtpUser().isEmpty() && !Env.smtpPass().isEmpty()) {
      String[] u = Env.smtpUser().split("@");
      String pass = Env.smtpPass();
      System.out.println("[email] Gmail account: " + (u[0].length() > 2 ? u[0].substring(0, 2) : u[0]) + "****@" + (u.length > 1 ? u[1] : "?")
          + " · App Password: " + pass.length() + " letters" + (pass.length() == 16 ? "" : " (should be 16)"));
    } else {
      System.out.println("[email] not set up: reset codes are printed here instead of emailed");
    }
    try {
      List<String> done = migrate.migrate();
      if (!done.isEmpty()) System.out.println("[database] updated: " + String.join(", ", done));
    } catch (Exception e) {
      System.err.println("[database] update skipped: " + e.getMessage());
    }
  }
}
