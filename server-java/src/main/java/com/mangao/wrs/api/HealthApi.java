package com.mangao.wrs.api;

import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.ErrorAdvice;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import java.time.Instant;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** GET /health - is the server running, and can it reach the database? */
@RestController
public class HealthApi {
  private final Db db;

  public HealthApi(Db db) {
    this.db = db;
  }

  @GetMapping("/")
  public Map<String, Object> root() {
    return M.of("app", "Mangao WRS API", "health", "/health");
  }

  @GetMapping("/health")
  public ResponseEntity<Map<String, Object>> health() {
    Map<String, Object> out = M.of("ok", true, "app", "mangao-system", "server", "java", "time", Clock.iso(Instant.now()));
    try {
      Map<String, Object> r = db.one("SELECT COUNT(*) AS users FROM users");
      out.put("database", "ok");
      out.put("users", V.lng(r.get("users")));
      return ResponseEntity.ok(out);
    } catch (Exception e) {
      out.put("ok", false);
      out.put("database", "error");
      out.put("reason", ErrorAdvice.DbHints.text(e));
      out.put("hint", ErrorAdvice.DbHints.hint(e));
      return ResponseEntity.status(503).body(out);
    }
  }
}
