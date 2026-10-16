package com.mangao.wrs.core;

import java.math.BigDecimal;
import java.math.BigInteger;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.Statement;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * MySQL helpers. Rows come back as maps (column name -> value) with:
 *  - DATETIME as Instant (the database keeps Philippine time),
 *  - DECIMAL and SUM() as Double, COUNT() as Long.
 * Parameters: an Instant is written as Philippine time; a Collection expands "IN (?)" to "IN (?, ?, ?)".
 * Inside tx(...) every query uses the same connection and transaction.
 */
@Component
public class Db {
  private final JdbcTemplate jdbc;
  private final TransactionTemplate tx;

  public Db(JdbcTemplate jdbc, TransactionTemplate tx) {
    this.jdbc = jdbc;
    this.tx = tx;
  }

  public JdbcTemplate jdbc() {
    return jdbc;
  }

  public List<Map<String, Object>> query(String sql, Object... params) {
    Prepared p = prepare(sql, params);
    return jdbc.query(p.sql, ps -> bind(ps, p.params), (ResultSet rs, int n) -> row(rs));
  }

  /** First row, or null. */
  public Map<String, Object> one(String sql, Object... params) {
    List<Map<String, Object>> rows = query(sql, params);
    return rows.isEmpty() ? null : rows.get(0);
  }

  /** UPDATE / DELETE: number of changed rows. */
  public int update(String sql, Object... params) {
    Prepared p = prepare(sql, params);
    return jdbc.update(p.sql, ps -> bind(ps, p.params));
  }

  /** INSERT: the new id. */
  public long insert(String sql, Object... params) {
    Prepared p = prepare(sql, params);
    KeyHolder kh = new GeneratedKeyHolder();
    jdbc.update(con -> {
      PreparedStatement ps = con.prepareStatement(p.sql, Statement.RETURN_GENERATED_KEYS);
      bind(ps, p.params);
      return ps;
    }, kh);
    Number k = kh.getKey();
    return k == null ? 0 : k.longValue();
  }

  /** Runs fn in one transaction; rolls back if it throws. */
  public <T> T tx(Supplier<T> fn) {
    return tx.execute(status -> fn.get());
  }

  public void txRun(Runnable fn) {
    tx.executeWithoutResult(status -> fn.run());
  }

  // ---------------------------------------------------------------- internals
  private record Prepared(String sql, List<Object> params) {}

  private static Prepared prepare(String sql, Object[] params) {
    boolean hasList = false;
    for (Object o : params) if (o instanceof Collection) hasList = true;
    if (!hasList) {
      List<Object> l = new ArrayList<>();
      for (Object o : params) l.add(o);
      return new Prepared(sql, l);
    }
    StringBuilder out = new StringBuilder();
    List<Object> flat = new ArrayList<>();
    int pi = 0;
    for (int i = 0; i < sql.length(); i++) {
      char c = sql.charAt(i);
      if (c == '?' && pi < params.length) {
        Object o = params[pi++];
        if (o instanceof Collection<?> col) {
          if (col.isEmpty()) {
            out.append("NULL");
          } else {
            int k = 0;
            for (Object x : col) {
              out.append(k++ == 0 ? "?" : ", ?");
              flat.add(x);
            }
          }
        } else {
          out.append('?');
          flat.add(o);
        }
      } else {
        out.append(c);
      }
    }
    return new Prepared(out.toString(), flat);
  }

  private static void bind(PreparedStatement ps, List<Object> params) throws java.sql.SQLException {
    for (int i = 0; i < params.size(); i++) {
      Object o = params.get(i);
      if (o instanceof Instant t) ps.setObject(i + 1, Clock.toLocal(t));
      else if (o instanceof Boolean b) ps.setInt(i + 1, b ? 1 : 0);
      else ps.setObject(i + 1, o);
    }
  }

  private static Map<String, Object> row(ResultSet rs) throws java.sql.SQLException {
    ResultSetMetaData md = rs.getMetaData();
    Map<String, Object> m = new LinkedHashMap<>();
    for (int c = 1; c <= md.getColumnCount(); c++) {
      String name = md.getColumnLabel(c);
      m.put(name, clean(rs.getObject(c)));
    }
    return m;
  }

  static Object clean(Object v) {
    if (v == null) return null;
    if (v instanceof LocalDateTime t) return Clock.fromLocal(t);
    if (v instanceof Timestamp t) return Clock.fromLocal(t.toLocalDateTime());
    if (v instanceof java.sql.Date d) return d.toLocalDate().toString();
    if (v instanceof LocalDate d) return d.toString();
    if (v instanceof BigDecimal b) return b.doubleValue();
    if (v instanceof BigInteger b) return b.longValue();
    if (v instanceof Boolean b) return b ? 1 : 0;
    if (v instanceof Short s) return s.intValue();
    if (v instanceof Byte b) return b.intValue();
    return v;
  }
}
