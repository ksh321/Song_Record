package com.ksh321.songrecord.api.auth;

import java.nio.file.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletResponse;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.bytes;

/** HTTP error envelopes after application wire conversion, not raw RevisionChanges maps. */
class MetadataConflictContractTests {
    private static final JsonMapper JSON=new JsonMapper();
    @Test void songConflictUsesPublicWireNamesEvenWhenClientBaselineIsAhead()throws Exception{
        var f=new SongEditingTests();f.open();
        try{
            f.setup.f.jdbc.update("UPDATE song SET revision=4 WHERE id=?",bytes(f.song));
            verify("SONG",f.edit("{\"base_revision\":5,\"note\":\"local\"}"));
        }finally{f.close();}
    }
    @Test void recordingConflictIncludesCompleteWireSnapshotEvenWhenClientBaselineIsAhead()throws Exception{
        var f=new RecordingEditingTests();f.open();
        try{
            assertThat(f.setup.create(f.setup.base()).getStatus()).isEqualTo(201);
            f.f.jdbc.update("UPDATE recording SET revision=4 WHERE id=?",bytes(f.setup.id));
            verify("RECORDING",f.edit(Map.of("base_revision",5,"note","local")));
        }finally{f.close();}
    }
    @Test void tagConflictUsesRevisionFieldsEvenWhenClientBaselineIsAhead()throws Exception{
        var f=new TagTests();f.open();
        try{
            UUID id=UUID.randomUUID();assertThat(f.create(id,"remote").getStatus()).isEqualTo(201);
            f.setup.f.jdbc.update("UPDATE tag SET revision=4 WHERE id=?",bytes(id));
            verify("TAG",f.rename(id,5,"local"));
        }finally{f.close();}
    }
    private static void verify(String entity,MockHttpServletResponse response)throws Exception{
        assertThat(response.getStatus()).isEqualTo(409);
        var error=JSON.readTree(response.getContentAsString()).get("error");
        assertThat(error.get("code").asText()).isEqualTo("REVISION_CONFLICT");
        var details=error.get("details");var current=details.get("current");
        assertThat(details.get("current_revision").asInt()).isEqualTo(4);
        assertThat(current.get("revision").asInt()).isEqualTo(4);
        var expected=JSON.readTree(Files.readString(Path.of("../../fixtures/contracts/metadata-response-fields.json"))).get(entity);
        var names=new HashSet<String>();for(var property:current.properties())names.add(property.getKey());
        var fields=new HashSet<String>();for(var field:expected)fields.add(field.asText());
        assertThat(names).isEqualTo(fields);
        Files.createDirectories(Path.of("build/conflict-evidence"));
        Files.writeString(Path.of("build/conflict-evidence/"+entity+".json"),current.toString());
    }
}
