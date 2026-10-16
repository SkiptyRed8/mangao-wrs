package com.mangao.wrs.core;

import java.util.LinkedHashMap;
import java.util.Map;

/** An error with the wording shown in the app: { error: { code, title, message, ...extra } }. */
public class HttpError extends RuntimeException {
  public final int status;
  public final String code;
  public final String title;
  public final Map<String, Object> extra;

  public HttpError(int status, String code, String title, String message, Map<String, Object> extra) {
    super(message);
    this.status = status;
    this.code = code;
    this.title = title;
    this.extra = extra == null ? new LinkedHashMap<>() : extra;
  }

  public HttpError(int status, String code, String title, String message) {
    this(status, code, title, message, null);
  }

  public static HttpError bad(String code, String title, String message, Object... extra) {
    return new HttpError(400, code, title, message, M.of(extra));
  }

  public static HttpError unauthorized(String code, String title, String message, Object... extra) {
    return new HttpError(401, code, title, message, M.of(extra));
  }

  public static HttpError forbidden(String code, String title, String message, Object... extra) {
    return new HttpError(403, code, title, message, M.of(extra));
  }

  public static HttpError notFound(String code, String title, String message, Object... extra) {
    return new HttpError(404, code, title, message, M.of(extra));
  }

  public static HttpError conflict(String code, String title, String message, Object... extra) {
    return new HttpError(409, code, title, message, M.of(extra));
  }

  public Map<String, Object> body() {
    Map<String, Object> e = M.of("code", code, "title", title, "message", getMessage());
    e.putAll(extra);
    return M.of("error", e);
  }
}
