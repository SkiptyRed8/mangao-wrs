package com.mangao.wrs.api;

import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.Env;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.M;
import com.mangao.wrs.service.Migrate;
import com.zaxxer.hikari.HikariDataSource;
import java.util.Map;
import javax.sql.DataSource;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Only for the automatic tests (NODE_ENV=test in .env; never on the laptop or online):
 * set the clock, run the start-up database update, and drop pooled connections after the test
 * database is rebuilt.
 */
@RestController
@RequestMapping("/__test")
public class TestApi {
  private final Migrate migrate;
  private final DataSource ds;

  public TestApi(Migrate migrate, DataSource ds) {
    this.migrate = migrate;
    this.ds = ds;
  }

  private static void only() {
    if (!Env.testMode()) throw new HttpError(404, "NOT_FOUND", "Not found", "Tests only.");
  }

  @PostMapping("/now")
  public Map<String, Object> now(@RequestBody(required = false) Map<String, Object> raw) {
    only();
    Object iso = new Body(raw).get("iso");
    Clock.setNow(iso == null ? null : String.valueOf(iso));
    return M.of("ok", true);
  }

  @PostMapping("/migrate")
  public Map<String, Object> migrate() {
    only();
    return M.of("done", migrate.migrate());
  }

  @PostMapping("/reset-pool")
  public Map<String, Object> resetPool() {
    only();
    if (ds instanceof HikariDataSource h && h.getHikariPoolMXBean() != null) h.getHikariPoolMXBean().softEvictConnections();
    return M.of("ok", true);
  }
}
