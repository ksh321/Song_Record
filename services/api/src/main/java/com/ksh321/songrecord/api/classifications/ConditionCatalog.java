package com.ksh321.songrecord.api.classifications;

import java.util.List;

/** D06 catalog v1; order and names match the immutable V4 database catalog. */
public final class ConditionCatalog {
    private ConditionCatalog() {}
    public record Item(String code, String name, int order, int catalog_version) {}
    public static final List<Item> ITEMS = List.of(
        new Item("VERY_GOOD", "매우 좋음", 1, 1), new Item("GOOD", "좋음", 2, 1),
        new Item("NORMAL", "보통", 3, 1), new Item("BAD", "안 좋음", 4, 1));
    public static boolean contains(String code) { return ITEMS.stream().anyMatch(i -> i.code().equals(code)); }
    public static String name(String code) { return ITEMS.stream().filter(i -> i.code().equals(code)).findFirst().orElseThrow().name(); }
}
