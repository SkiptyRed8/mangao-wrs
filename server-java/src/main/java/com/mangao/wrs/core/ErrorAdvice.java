package com.mangao.wrs.core;

import jakarta.servlet.http.HttpServletRequest;
import java.sql.SQLException;
import java.util.Map;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.jdbc.CannotGetJdbcConnectionException;
import org.springframework.web.HttpMediaTypeNotSupportedException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.resource.NoResourceFoundException;

/** Every error as { error: { code, title, message } } with the wording shown in the app. */
@RestControllerAdvice
public class ErrorAdvice {

  @ExceptionHandler(HttpError.class)
  public ResponseEntity<Map<String, Object>> http(HttpError e) {
    return ResponseEntity.status(e.status).body(e.body());
  }

  @ExceptionHandler({NoResourceFoundException.class, HttpRequestMethodNotSupportedException.class})
  public ResponseEntity<Map<String, Object>> notFound(HttpServletRequest req) {
    return ResponseEntity.status(404)
        .body(new HttpError(404, "NOT_FOUND", "Not found", req.getMethod() + " " + req.getRequestURI() + " does not exist.").body());
  }

  @ExceptionHandler({HttpMessageNotReadableException.class, HttpMediaTypeNotSupportedException.class})
  public ResponseEntity<Map<String, Object>> badJson() {
    return ResponseEntity.status(400)
        .body(new HttpError(400, "BAD_JSON", "Something went wrong", "The app sent data the server could not read.").body());
  }

  @ExceptionHandler(Exception.class)
  public ResponseEntity<Map<String, Object>> other(Exception e) {
    String hint = DbHints.hint(e);
    if (hint != null) {
      System.err.println("[database] " + hint);
      return ResponseEntity.status(503)
          .body(new HttpError(503, "DATABASE", "The system is not ready", "The database is not available. Try again in a moment.").body());
    }
    e.printStackTrace();
    return ResponseEntity.status(500).body(new HttpError(500, "SERVER_ERROR", "Something went wrong", "Please try again.").body());
  }

  /** Plain-language hints for the usual database problems on the laptop (XAMPP). */
  public static final class DbHints {
    private DbHints() {}

    public static String hint(Throwable e) {
      for (Throwable t = e; t != null; t = t.getCause()) {
        String m = String.valueOf(t.getMessage());
        if (t instanceof CannotGetJdbcConnectionException || t instanceof DataAccessResourceFailureException
            || m.contains("Communications link failure") || m.contains("Connection refused")) {
          if (m.contains("Access denied")) return "Wrong MySQL user or password. Check DB_USER and DB_PASSWORD in server-java/.env (XAMPP: root and an empty password).";
          if (m.contains("Unknown database")) return "The database does not exist yet. Double-click RESET-DEMO-DATA.bat.";
          if (t.getCause() == null || m.contains("Communications link failure") || m.contains("Connection refused")) {
            return "MySQL is not running. Open the XAMPP Control Panel and press Start beside MySQL (or double-click START.bat).";
          }
        }
        if (t instanceof SQLException s) {
          if (s.getErrorCode() == 1045) return "Wrong MySQL user or password. Check DB_USER and DB_PASSWORD in server-java/.env (XAMPP: root and an empty password).";
          if (s.getErrorCode() == 1049) return "The database does not exist yet. Double-click RESET-DEMO-DATA.bat.";
          if (s.getErrorCode() == 1146) return "A table is missing. Double-click RESET-DEMO-DATA.bat.";
        }
      }
      return null;
    }

    public static String text(Throwable e) {
      Throwable root = e;
      while (root.getCause() != null) root = root.getCause();
      return root.getClass().getSimpleName() + " " + root.getMessage();
    }
  }
}
