package com.mangao.wrs.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Component;

/**
 * Routes along the streets for the live map and the demo ride. Asks the free OSRM route service
 * (open-source routing on OpenStreetMap roads); if it does not answer, a straight line is used.
 * The server asks (not the phone), so it also works in the web version and answers are cached.
 */
@Component
public class Routes {
  private static final String OSRM = "https://router.project-osrm.org/route/v1/driving/";
  /** About 20 km/h in city traffic, for the straight-line estimate. */
  public static final double CITY_SPEED = 20000 / 3600.0;
  private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(6)).build();
  private final ObjectMapper json = new ObjectMapper();
  private final Map<String, Route> cache = new ConcurrentHashMap<>();

  /** points: [lat, lng] pairs; meters and seconds of the whole route; streets false = straight line. */
  public record Route(List<double[]> points, double meters, double seconds, boolean streets) {}

  public static double meters(double lat1, double lng1, double lat2, double lng2) {
    double r = 6371000, dLat = Math.toRadians(lat2 - lat1), dLng = Math.toRadians(lng2 - lng1);
    double h = Math.pow(Math.sin(dLat / 2), 2)
        + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) * Math.pow(Math.sin(dLng / 2), 2);
    return 2 * r * Math.asin(Math.min(1, Math.sqrt(h)));
  }

  /** Straight lines through the stops. */
  public static Route straight(List<double[]> stops) {
    double m = 0;
    for (int i = 0; i + 1 < stops.size(); i++) m += meters(stops.get(i)[0], stops.get(i)[1], stops.get(i + 1)[0], stops.get(i + 1)[1]);
    return new Route(new ArrayList<>(stops), m, m / CITY_SPEED, false);
  }

  /** The route through [lat, lng] stops in order (at least 2). */
  public Route route(List<double[]> stops) {
    StringBuilder path = new StringBuilder();
    for (double[] p : stops) {
      if (path.length() > 0) path.append(';');
      path.append(String.format(Locale.ROOT, "%.6f,%.6f", p[1], p[0]));
    }
    String key = path.toString();
    Route hit = cache.get(key);
    if (hit != null) return hit;
    try {
      HttpResponse<String> res = http.send(HttpRequest.newBuilder(URI.create(OSRM + key + "?overview=full&geometries=geojson"))
          .header("User-Agent", "MangaoWRS/1.0 (school project, Quezon City)")
          .timeout(Duration.ofSeconds(8)).GET().build(), HttpResponse.BodyHandlers.ofString());
      if (res.statusCode() == 200) {
        JsonNode d = json.readTree(res.body());
        JsonNode r = d.path("routes").path(0);
        if ("Ok".equals(d.path("code").asText()) && !r.isMissingNode()) {
          List<double[]> pts = new ArrayList<>();
          for (JsonNode c : r.path("geometry").path("coordinates")) pts.add(new double[] {c.get(1).asDouble(), c.get(0).asDouble()});
          if (pts.size() >= 2) {
            Route out = new Route(pts, r.path("distance").asDouble(), r.path("duration").asDouble(), true);
            if (cache.size() > 300) cache.clear();
            cache.put(key, out);
            return out;
          }
        }
      }
    } catch (Exception e) {
      // fall through to the straight line
    }
    return straight(stops);
  }
}
