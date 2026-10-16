package com.mangao.wrs.api;

import com.mangao.wrs.core.Auth;
import com.mangao.wrs.core.Body;
import com.mangao.wrs.core.Db;
import com.mangao.wrs.core.HttpError;
import com.mangao.wrs.core.M;
import com.mangao.wrs.core.V;
import com.mangao.wrs.service.Addresses;
import jakarta.servlet.http.HttpServletRequest;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Saved addresses (Customer 7): add (pin on map or type the address), edit, delete. */
@RestController
@RequestMapping("/api/addresses")
public class AddressesApi {
  private static final int MAX_ADDRESSES = 10;
  private static final String COLS = "address_name = ?, house_unit_no = ?, block_lot = ?, street = ?, barangay = ?, landmark = ?, latitude = ?, longitude = ?";
  private final Db db;
  private final Auth auth;

  public AddressesApi(Db db, Auth auth) {
    this.db = db;
    this.auth = auth;
  }

  private static String readName(Body b) {
    String name = b.text("name", 50);
    if (name.isEmpty()) throw HttpError.bad("NAME_MISSING", "Name missing", "Type a name, like Home or Work.", "field", "name");
    return name;
  }

  private static Object orNull(Object v) {
    return V.truthy(v) ? v : null;
  }

  private static Object[] values(String name, Map<String, Object> a, Object... more) {
    List<Object> l = new ArrayList<>(List.of(name));
    for (String k : List.of("house", "blockLot", "street", "barangay", "landmark")) l.add(orNull(a.get(k)));
    l.add(a.get("lat"));
    l.add(a.get("lng"));
    for (Object o : more) l.add(o);
    return l.toArray();
  }

  private Map<String, Object> mine(HttpServletRequest req, String id) {
    Map<String, Object> me = auth.require(req, "Customer");
    Map<String, Object> r = db.one("SELECT * FROM customer_addresses WHERE address_id = ? AND customer_id = ?", StaffApi.idOf(id), Auth.id(me));
    if (r == null) throw HttpError.notFound("ADDRESS_NOT_FOUND", "Address not found", "It may have been deleted.");
    return r;
  }

  private Map<String, Object> shaped(long id) {
    return Addresses.shapeAddress(db.one("SELECT * FROM customer_addresses WHERE address_id = ?", id));
  }

  /** GET /api/addresses -> { addresses } */
  @GetMapping
  public Map<String, Object> list(HttpServletRequest req) {
    Map<String, Object> me = auth.require(req, "Customer");
    List<Map<String, Object>> out = new ArrayList<>();
    for (Map<String, Object> r : db.query("SELECT * FROM customer_addresses WHERE customer_id = ? ORDER BY address_id", Auth.id(me))) {
      out.add(Addresses.shapeAddress(r));
    }
    return M.of("addresses", out);
  }

  /** POST /api/addresses { name, mode, house, blockLot, street, barangay, landmark, lat, lng } -> 201 { address } */
  @PostMapping
  public ResponseEntity<Map<String, Object>> add(HttpServletRequest req, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> me = auth.require(req, "Customer");
    Body b = new Body(raw);
    String name = readName(b);
    Map<String, Object> a = Addresses.readAddress(b);
    Map<String, Object> n = db.one("SELECT COUNT(*) AS n FROM customer_addresses WHERE customer_id = ?", Auth.id(me));
    if (V.lng(n.get("n")) >= MAX_ADDRESSES) throw HttpError.bad("TOO_MANY", "Too many addresses", "Keep up to " + MAX_ADDRESSES + ". Delete one first.");
    Object[] vals = values(name, a);
    Object[] all = new Object[vals.length + 1];
    all[0] = Auth.id(me);
    System.arraycopy(vals, 0, all, 1, vals.length);
    long id = db.insert("INSERT INTO customer_addresses SET customer_id = ?, " + COLS, all);
    return ResponseEntity.status(201).body(M.of("address", shaped(id), "message", "Address saved"));
  }

  /** PUT /api/addresses/:id -> { address } */
  @PutMapping("/{id}")
  public Map<String, Object> edit(HttpServletRequest req, @PathVariable String id, @RequestBody(required = false) Map<String, Object> raw) {
    Map<String, Object> row = mine(req, id);
    Body b = new Body(raw);
    String name = readName(b);
    Map<String, Object> a = Addresses.readAddress(b);
    db.update("UPDATE customer_addresses SET " + COLS + " WHERE address_id = ?", values(name, a, row.get("address_id")));
    return M.of("address", shaped(V.lng(row.get("address_id"))), "message", "Address updated");
  }

  /** DELETE /api/addresses/:id -> { ok } (past orders keep their own copy of the address) */
  @DeleteMapping("/{id}")
  public Map<String, Object> delete(HttpServletRequest req, @PathVariable String id) {
    Map<String, Object> row = mine(req, id);
    db.update("DELETE FROM customer_addresses WHERE address_id = ?", row.get("address_id"));
    return M.of("ok", true, "message", "Address deleted");
  }
}
