package com.mangao.wrs.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Delivery addresses (Customer 3A, Customer 7): pinned on the map or typed.
 * Customers are in Quezon City, so only house / unit no., block / lot, street and barangay are asked.
 */
public final class Addresses {
  public static final List<String> BARANGAYS = load();
  private static final Map<String, String> BY_LOWER = new LinkedHashMap<>();

  static {
    for (String b : BARANGAYS) BY_LOWER.put(b.toLowerCase(), b);
  }

  private Addresses() {}

  private static List<String> load() {
    try (InputStream in = Addresses.class.getResourceAsStream("/data/qc-barangays.json")) {
      return Arrays.asList(new ObjectMapper().readValue(in, String[].class));
    } catch (Exception e) {
      throw new IllegalStateException("qc-barangays.json missing", e);
    }
  }

  /** Philippines box; the pin must be on land near Metro Manila to be used. */
  public static boolean inArea(double lat, double lng) {
    return lat > 14.3 && lat < 15.0 && lng > 120.8 && lng < 121.3;
  }

  private static Double coord(Object v) {
    if (v == null || "".equals(v)) return null;
    return V.num(v);
  }

  private static boolean finite(Double d) {
    return d != null && !d.isNaN() && !d.isInfinite();
  }

  /**
   * Reads { mode: 'pin'|'typed', house, blockLot, street, barangay, landmark, lat, lng } and returns the
   * clean fields plus the one-line text. Pinned: lat/lng needed. Typed: house, street and barangay needed.
   */
  public static Map<String, Object> readAddress(Body b) {
    boolean pinned = "pin".equals(b.get("mode"));
    Map<String, Object> a = M.of(
        "pinned", pinned,
        "house", b.text("house", 20),
        "blockLot", b.text("blockLot", 30),
        "street", b.text("street", 100),
        "barangay", b.text("barangay", 60),
        "landmark", b.text("landmark", 150),
        "lat", coord(b.get("lat")),
        "lng", coord(b.get("lng")));
    String brgy = (String) a.get("barangay");
    if (!brgy.isEmpty()) a.put("barangay", BY_LOWER.getOrDefault(brgy.toLowerCase(), brgy));
    Double lat = (Double) a.get("lat"), lng = (Double) a.get("lng");
    if (pinned) {
      if (!finite(lat) || !finite(lng)) throw HttpError.bad("PIN_MISSING", "Pin missing", "Move the map to place the pin.", "field", "pin");
      if (!inArea(lat, lng)) throw HttpError.bad("OUTSIDE_AREA", "Outside delivery area", "Place the pin in Quezon City.", "field", "pin");
    } else {
      List<String> missing = new ArrayList<>();
      if (((String) a.get("house")).isEmpty()) missing.add("house");
      if (((String) a.get("street")).isEmpty()) missing.add("street");
      if (((String) a.get("barangay")).isEmpty()) missing.add("barangay");
      if (!missing.isEmpty()) {
        throw HttpError.bad("ADDRESS_MISSING", "Fill in the missing fields", "House / unit no., Street and Barangay are needed", "fields", missing);
      }
      if (!BY_LOWER.containsKey(((String) a.get("barangay")).toLowerCase())) {
        throw HttpError.bad("BARANGAY_UNKNOWN", "Choose a barangay", "Pick it from the Quezon City list.", "fields", List.of("barangay"));
      }
      if (!finite(lat) || !finite(lng) || !inArea(lat, lng)) {
        a.put("lat", null);
        a.put("lng", null);
      }
    }
    a.put("text", Orders.addressText(a));
    return a;
  }

  /** A saved address row -> the app's address object. */
  public static Map<String, Object> shapeAddress(Map<String, Object> r) {
    Map<String, Object> a = M.of(
        "id", V.lng(r.get("address_id")),
        "name", r.get("address_name"),
        "house", V.s(r.get("house_unit_no")),
        "blockLot", V.s(r.get("block_lot")),
        "street", V.s(r.get("street")),
        "barangay", V.s(r.get("barangay")),
        "city", r.get("city"),
        "landmark", V.s(r.get("landmark")),
        "lat", V.numOrNull(r.get("latitude")),
        "lng", V.numOrNull(r.get("longitude")));
    a.put("mode", V.truthy(a.get("house")) ? "typed" : "pin");
    a.put("pinned", "pin".equals(a.get("mode")));
    a.put("text", Orders.addressText(a));
    return a;
  }
}
