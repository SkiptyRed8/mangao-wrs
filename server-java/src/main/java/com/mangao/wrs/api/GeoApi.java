package com.mangao.wrs.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import com.mangao.wrs.service.Addresses;
import com.mangao.wrs.service.Routes;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Map helpers for the address pin: the Quezon City barangay list, "Pinned: near ..." text for a pin,
 * and street / place search. Pin text and search use OpenStreetMap Nominatim (free) from the server,
 * with a short cache; if it cannot be reached, the app still works with the pin alone.
 */
@RestController
@RequestMapping("/api/geo")
public class GeoApi {
  private static final String NOMINATIM = "https://nominatim.openstreetmap.org";
  private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(6)).build();
  private final ObjectMapper json = new ObjectMapper();
  private final Map<String, JsonNode> cache = new ConcurrentHashMap<>();
  private final Routes routes;

  public GeoApi(Routes routes) {
    this.routes = routes;
  }

  private JsonNode nominatim(String path) {
    JsonNode c = cache.get(path);
    if (c != null) return c;
    HttpError offline = new HttpError(503, "MAP_OFFLINE", "Map search not available", "Move the pin by hand, or type the address.");
    try {
      HttpResponse<String> res = http.send(HttpRequest.newBuilder(URI.create(NOMINATIM + path))
          .header("User-Agent", "MangaoWRS/1.0 (school project, Quezon City)")
          .header("Accept-Language", "en")
          .timeout(Duration.ofSeconds(6))
          .GET().build(), HttpResponse.BodyHandlers.ofString());
      if (res.statusCode() != 200) throw offline;
      JsonNode d = json.readTree(res.body());
      if (cache.size() > 500) cache.clear();
      cache.put(path, d);
      return d;
    } catch (HttpError e) {
      throw e;
    } catch (Exception e) {
      throw offline;
    }
  }

  /** Nominatim address -> our fields (barangay = the QC barangay when the name matches). */
  private static Map<String, Object> fields(JsonNode addr) {
    List<String> candidates = new ArrayList<>();
    for (String k : List.of("quarter", "neighbourhood", "suburb", "village", "city_district")) {
      if (addr != null && addr.hasNonNull(k) && !addr.get(k).asText().isEmpty()) candidates.add(addr.get(k).asText());
    }
    String barangay = null;
    for (String c : candidates) {
      String n = c.replaceFirst("(?i)^barangay ", "").toLowerCase();
      for (String b : Addresses.BARANGAYS) if (b.toLowerCase().equals(n)) { barangay = b; break; }
      if (barangay != null) break;
    }
    if (barangay == null) barangay = candidates.isEmpty() ? "" : candidates.get(0);
    String street = "";
    for (String k : List.of("road", "pedestrian", "residential")) {
      if (addr != null && addr.hasNonNull(k) && !addr.get(k).asText().isEmpty()) { street = addr.get(k).asText(); break; }
    }
    String house = addr != null && addr.hasNonNull("house_number") ? addr.get("house_number").asText() : "";
    return M.of("house", house, "street", street, "barangay", barangay);
  }

  /** GET /api/geo/barangays -> { barangays } (A to Z) */
  @GetMapping("/barangays")
  public Map<String, Object> barangays() {
    return M.of("barangays", Addresses.BARANGAYS, "city", "Quezon City");
  }

  /** GET /api/geo/reverse?lat=&lng= -> { street, barangay, label } */
  @GetMapping("/reverse")
  public Map<String, Object> reverse(@RequestParam(required = false) String lat, @RequestParam(required = false) String lng) {
    double la = lat == null ? Double.NaN : V.num(lat), ln = lng == null ? Double.NaN : V.num(lng);
    if (Double.isNaN(la) || Double.isNaN(ln) || !Addresses.inArea(la, ln)) throw HttpError.bad("OUTSIDE_AREA", "Outside delivery area", "Place the pin in Quezon City.");
    String key = String.format(java.util.Locale.ROOT, "/reverse?format=jsonv2&zoom=18&addressdetails=1&lat=%.5f&lon=%.5f", la, ln);
    JsonNode d = nominatim(key);
    Map<String, Object> f = fields(d.get("address"));
    String first = String.join(" ", Arrays.stream(new String[] {(String) f.get("house"), (String) f.get("street")}).filter(s -> !s.isEmpty()).toList());
    String label = String.join(", ", Arrays.stream(new String[] {first, (String) f.get("barangay")}).filter(s -> !s.isEmpty()).toList());
    return M.with(f, "label", label.isEmpty() ? "the map pin" : label);
  }

  /** GET /api/geo/search?q= -> { results: [{ label, lat, lng }] } (Quezon City only) */
  @GetMapping("/search")
  public Map<String, Object> search(@RequestParam(required = false) String q) {
    String text = Body.textOf(q, 100);
    if (text.length() < 3) return M.of("results", List.of());
    String key = "/search?format=jsonv2&addressdetails=1&limit=6&countrycodes=ph&bounded=1&viewbox=120.98,14.78,121.14,14.58&q="
        + URLEncoder.encode(text, StandardCharsets.UTF_8).replace("+", "%20");
    JsonNode d = nominatim(key);
    List<Map<String, Object>> out = new ArrayList<>();
    for (JsonNode r : d) {
      String[] parts = r.path("display_name").asText().split(", ");
      out.add(M.of("label", String.join(", ", Arrays.copyOfRange(parts, 0, Math.min(3, parts.length))),
          "lat", V.num(r.path("lat").asText()), "lng", V.num(r.path("lon").asText())));
    }
    return M.of("results", out);
  }

  private static double[] point(String text) {
    String[] p = text == null ? new String[0] : text.split(",");
    double lat = p.length == 2 ? V.num(p[0].trim()) : Double.NaN, lng = p.length == 2 ? V.num(p[1].trim()) : Double.NaN;
    if (Double.isNaN(lat) || Double.isNaN(lng) || lat < 4 || lat > 22 || lng < 116 || lng > 127) {
      throw HttpError.bad("LOCATION_INVALID", "Location not valid", "The map could not use this place.");
    }
    return new double[] {lat, lng};
  }

  /**
   * GET /api/geo/route?from=lat,lng&to=lat,lng -> { points: [[lat, lng], ...], meters, seconds, streets }
   * The route along the streets for the live map (streets false: a straight line, the route service did not answer).
   */
  @GetMapping("/route")
  public Map<String, Object> route(@RequestParam(required = false) String from, @RequestParam(required = false) String to) {
    Routes.Route r = routes.route(List.of(point(from), point(to)));
    List<List<Double>> pts = new ArrayList<>();
    for (double[] p : r.points()) pts.add(List.of(Math.round(p[0] * 1e6) / 1e6, Math.round(p[1] * 1e6) / 1e6));
    return M.of("points", pts, "meters", Math.round(r.meters()), "seconds", Math.round(r.seconds()), "streets", r.streets());
  }
}
