package com.mangao.wrs.api;

import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.Env;
import com.mangao.wrs.core.HttpError;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

/**
 * GET /uploads/damage/{file}: a damaged-gallon photo. Online the photos are in the database
 * (stored_files); on the laptop they are files in server-java/uploads/damage. Names are random, so
 * the link itself is the permission (like the old server's static folder).
 */
@RestController
public class UploadsApi {
  private final Db db;

  public UploadsApi(Db db) {
    this.db = db;
  }

  @GetMapping("/uploads/damage/{file:[0-9a-f]{32}\\.(?:jpg|png|webp)}")
  public ResponseEntity<byte[]> photo(@PathVariable String file) throws Exception {
    String key = "damage/" + file;
    byte[] data;
    String type;
    Map<String, Object> row;
    try {
      row = db.one("SELECT content_type, data FROM stored_files WHERE file_path = ?", key);
    } catch (org.springframework.dao.DataAccessException e) {
      row = null; // older database without the table: look on disk
    }
    if (row != null) {
      data = (byte[]) row.get("data");
      type = String.valueOf(row.get("content_type"));
    } else {
      Path p = Env.uploadsDir().resolve(key).normalize();
      if (!p.startsWith(Env.uploadsDir()) || !Files.isRegularFile(p)) throw HttpError.notFound("PHOTO_NOT_FOUND", "Photo not found", "It may have been removed.");
      data = Files.readAllBytes(p);
      type = file.endsWith(".png") ? "image/png" : file.endsWith(".webp") ? "image/webp" : "image/jpeg";
    }
    return ResponseEntity.ok().contentType(MediaType.parseMediaType(type)).cacheControl(CacheControl.maxAge(7, TimeUnit.DAYS)).body(data);
  }
}
