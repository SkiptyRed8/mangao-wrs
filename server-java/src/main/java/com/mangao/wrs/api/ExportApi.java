package com.mangao.wrs.api;

import com.mangao.wrs.core.Auth;
import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Clock;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.Jwt;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import com.mangao.wrs.service.Export;
import jakarta.servlet.http.HttpServletRequest;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Export Report (Admin Sales 4). The owner chooses the report, date and format; the server gives a
 * download link that works for 5 minutes (so the log-in token never goes in a web address).
 *  POST /api/export { report: daily|weekly|unpaid, date, format: pdf|xlsx } -> { fileName, url, message }
 *  GET  /api/export/file?ticket=... -> the file (Content-Disposition: attachment)
 */
@RestController
@RequestMapping("/api/export")
public class ExportApi {
  private static final List<String> REPORTS = List.of("daily", "weekly", "unpaid");
  private static final List<String> FORMATS = List.of("pdf", "xlsx");
  private final Db db;
  private final Auth auth;
  private final Export export;

  public ExportApi(Db db, Auth auth, Export export) {
    this.db = db;
    this.auth = auth;
    this.export = export;
  }

  private static String check(Object report, Object date, Object format) {
    if (!(report instanceof String) || !REPORTS.contains(report)) throw HttpError.bad("REPORT_MISSING", "Choose a report", "Daily, Weekly or Unpaid accounts.");
    if (!(format instanceof String) || !FORMATS.contains(format)) throw HttpError.bad("FORMAT_MISSING", "Choose a format", "PDF or Spreadsheet.");
    String today = Clock.ymd(Clock.now());
    String d = V.truthy(date) ? V.str(date) : today;
    if (!d.matches("^\\d{4}-\\d{2}-\\d{2}$")) throw HttpError.bad("DATE_INVALID", "Date not valid", "Pick the date again.");
    if (d.compareTo(today) > 0) throw HttpError.bad("DATE_FUTURE", "No sales yet", "Pick today or an earlier day.");
    return d;
  }

  @PostMapping
  public Map<String, Object> create(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) throws Exception {
    Map<String, Object> me = auth.require(req, "Owner");
    Body b = new Body(raw);
    String date = check(b.get("report"), b.get("date"), b.get("format"));
    String report = (String) b.get("report"), format = (String) b.get("format");
    String ticket = Jwt.sign(M.of("sub", Auth.id(me), "report", report, "date", date, "format", format, "kind", "export"), 5 * 60);
    // Build it once now so problems show here and the name is known.
    Export.File f = export.exportFile(report, date, format);
    return M.of("fileName", f.fileName(), "url", "/api/export/file?ticket=" + URLEncoder.encode(ticket, StandardCharsets.UTF_8), "message", "File ready");
  }

  @GetMapping("/file")
  public ResponseEntity<byte[]> file(@RequestParam(required = false) String ticket) throws Exception {
    HttpError expired = HttpError.unauthorized("LINK_EXPIRED", "Link expired", "Tap Create file again.");
    Map<String, Object> t = Jwt.verify(ticket);
    if (t == null || !"export".equals(t.get("kind"))) throw expired;
    Map<String, Object> u = db.one("SELECT is_active FROM users WHERE user_id = ? AND role = 'Owner'", V.lng(t.get("sub")));
    if (u == null || !V.truthy(u.get("is_active"))) throw expired;
    Export.File f = export.exportFile(String.valueOf(t.get("report")), check(t.get("report"), t.get("date"), t.get("format")), String.valueOf(t.get("format")));
    return ResponseEntity.ok()
        .header(HttpHeaders.CONTENT_TYPE, f.type())
        .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + f.fileName() + "\"")
        .header(HttpHeaders.CACHE_CONTROL, "no-store")
        .body(f.bytes());
  }
}
