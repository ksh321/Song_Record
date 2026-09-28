package com.ksh321.songrecord.api.classifications;

import java.util.Set;
import java.util.UUID;

/** Legacy defaults remain codes; custom definitions use their canonical UUID as code. */
public final class ConditionReference {
    private ConditionReference(){}
    public static boolean valid(String code){
        if(code==null)return false;
        if(Set.of("VERY_GOOD","GOOD","NORMAL","BAD").contains(code))return true;
        try{return UUID.fromString(code).toString().equals(code);}catch(IllegalArgumentException e){return false;}
    }
}
