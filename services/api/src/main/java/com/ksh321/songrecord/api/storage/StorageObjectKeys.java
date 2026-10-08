package com.ksh321.songrecord.api.storage;

import java.util.Objects;
import java.util.UUID;

/** Only server-owned IDs; no filename or arbitrary client path is accepted. */
public final class StorageObjectKeys {
    private StorageObjectKeys() {}
    public record Temporary(UUID owner,UUID recording,UUID attempt) {
        public Temporary {valid(owner);valid(recording);valid(attempt);}
        public String value(){return "temporary/"+owner+"/"+recording+"/"+attempt;}
    }
    public record Final(UUID owner,UUID recording,UUID generation) {
        public Final {valid(owner);valid(recording);valid(generation);}
        public String value(){return "recordings/"+owner+"/"+recording+"/"+generation+".m4a";}
    }
    private static void valid(UUID id){Objects.requireNonNull(id);if(id.equals(new UUID(0,0)))throw new IllegalArgumentException("Object ID must be nonzero");}
}
