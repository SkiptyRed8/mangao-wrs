package com.mangao.wrs.core;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** JSON-like objects: keys keep their order and values may be null (like the old JavaScript objects). */
public final class M {
  private M() {}

  public static Map<String, Object> of(Object... kv) {
    Map<String, Object> m = new LinkedHashMap<>();
    for (int i = 0; i + 1 < kv.length; i += 2) m.put((String) kv[i], kv[i + 1]);
    return m;
  }

  @SafeVarargs
  public static <T> List<T> list(T... items) {
    List<T> l = new ArrayList<>();
    for (T t : items) l.add(t);
    return l;
  }

  /** A copy with more keys (later keys replace earlier ones), like { ...a, k: v }. */
  public static Map<String, Object> with(Map<String, Object> base, Object... kv) {
    Map<String, Object> m = new LinkedHashMap<>(base);
    m.putAll(of(kv));
    return m;
  }
}
