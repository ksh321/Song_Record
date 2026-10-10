package com.ksh321.songrecord.api.charts;

import java.util.*;
import tools.jackson.core.StreamReadFeature;
import tools.jackson.databind.*;
import tools.jackson.databind.json.JsonMapper;

/** Validate all received rows before any chart item can be published; never repair provider content. */
public final class ChartValidation {
    public record Item(int position,String number,String title,String artist){}
    public enum Failure { INVALID_JSON, EMPTY, INVALID_ITEM, WRONG_BRAND, DUPLICATE_NUMBER }
    public static final class InvalidChart extends RuntimeException {
        private final Failure kind;public InvalidChart(Failure kind){super(kind.name());this.kind=kind;}public Failure kind(){return kind;}
    }
    private final JsonMapper json=JsonMapper.builder().enable(StreamReadFeature.STRICT_DUPLICATE_DETECTION).enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS).build();
    public List<Item> validate(ChartScope scope,byte[] payload){
        Objects.requireNonNull(scope);
        if(payload==null || payload.length==0 || payload.length>ChartStaging.MAX_BYTES)throw new InvalidChart(Failure.INVALID_JSON);
        JsonNode root;try{root=json.readTree(payload);}catch(Exception e){throw new InvalidChart(Failure.INVALID_JSON);}
        if(root==null || !root.isArray())throw new InvalidChart(Failure.INVALID_JSON);
        if(root.isEmpty())throw new InvalidChart(Failure.EMPTY);
        var numbers=new HashSet<String>();var items=new ArrayList<Item>();
        for(var row:root){
            if(!row.isObject())throw new InvalidChart(Failure.INVALID_ITEM);
            if(!scope.providerBrand().equals(text(row,"brand")))throw new InvalidChart(Failure.WRONG_BRAND);
            var number=text(row,"no");var title=text(row,"title");var artist=text(row,"singer");
            if(!number.matches("[0-9]{1,20}") || !validText(title) || !validText(artist))throw new InvalidChart(Failure.INVALID_ITEM);
            if(!numbers.add(number))throw new InvalidChart(Failure.DUPLICATE_NUMBER);
            items.add(new Item(items.size()+1,number,title,artist));
        }
        return List.copyOf(items);
    }
    private String text(JsonNode row,String key){var value=row.get(key);if(value==null || !value.isString())throw new InvalidChart(Failure.INVALID_ITEM);return value.asString();}
    private boolean validText(String text){
        if(text.isBlank() || text.codePointCount(0,text.length())>200)return false;
        for(int i=0;i<text.length();i++){char c=text.charAt(i);if(Character.isHighSurrogate(c)){if(++i>=text.length() || !Character.isLowSurrogate(text.charAt(i)))return false;}else if(Character.isLowSurrogate(c))return false;}
        return true;
    }
}
