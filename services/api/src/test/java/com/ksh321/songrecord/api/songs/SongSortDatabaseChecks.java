package com.ksh321.songrecord.api.songs;

import com.ksh321.songrecord.api.domain.DomainOrdering;
import java.nio.ByteBuffer;
import java.nio.file.*;
import java.util.*;
import org.springframework.jdbc.core.JdbcTemplate;
import tools.jackson.databind.json.JsonMapper;
import static org.assertj.core.api.Assertions.*;

/** Same SQL checks on H2 and MySQL: binary collation, equal keys, prefix keys, and cursor boundaries. */
public final class SongSortDatabaseChecks {
    private SongSortDatabaseChecks() {}
    public static void verify(JdbcTemplate jdbc) throws Exception {
        jdbc.execute("CREATE TABLE song_sort_probe(id BINARY(16) PRIMARY KEY,sort_key VARBINARY(2048) NOT NULL)");
        var fixture=new JsonMapper().readTree(Files.readString(Path.of("../../fixtures/contracts/sorting.json")));
        for(var test:fixture.get("cases")){
            jdbc.update("DELETE FROM song_sort_probe");
            for(var row:test.get("input").get("rows"))jdbc.update("INSERT INTO song_sort_probe VALUES(?,?)",
                    bytes(UUID.fromString(row.get("id").asText())),DomainOrdering.sortKeyBytes(row.get("title").asText()));
            var expected=new ArrayList<String>();test.get("expected").get("ids").forEach(n->expected.add(n.asText()));
            assertThat(jdbc.query("SELECT id FROM song_sort_probe ORDER BY sort_key,id",(rs,n)->uuid(rs.getBytes(1)).toString()))
                    .as(test.get("id").asText()).containsExactlyElementsOf(expected);
            var paged=new ArrayList<String>();byte[] afterKey=null,afterId=null;
            while(true){
                List<Map<String,Object>> page;
                if(afterId==null)page=jdbc.query("SELECT id,sort_key FROM song_sort_probe ORDER BY sort_key,id LIMIT 2",(rs,n)->Map.of("id",rs.getBytes(1),"key",rs.getBytes(2)));
                else page=jdbc.query("SELECT id,sort_key FROM song_sort_probe WHERE sort_key>? OR (sort_key=? AND id>?) ORDER BY sort_key,id LIMIT 2",
                        (rs,n)->Map.of("id",rs.getBytes(1),"key",rs.getBytes(2)),afterKey,afterKey,afterId);
                if(page.isEmpty())break;
                page.forEach(row->paged.add(uuid((byte[])row.get("id")).toString()));
                assertThat(paged.size()).isLessThanOrEqualTo(expected.size());
                afterKey=(byte[])page.getLast().get("key");afterId=(byte[])page.getLast().get("id");
            }
            assertThat(paged).containsExactlyElementsOf(expected);
        }
        // A zero scalar inside a character token must not be confused with the end marker.
        jdbc.update("DELETE FROM song_sort_probe");
        String[] values={"a\u0000b","a0","a\u0000","a"};
        for(int i=0;i<values.length;i++)jdbc.update("INSERT INTO song_sort_probe VALUES(?,?)",bytes(new UUID(0,i+1)),DomainOrdering.sortKeyBytes(values[i]));
        assertThat(jdbc.query("SELECT id FROM song_sort_probe ORDER BY sort_key,id",(rs,n)->uuid(rs.getBytes(1)).getLeastSignificantBits())).containsExactly(4L,2L,3L,1L);
    }
    private static byte[] bytes(UUID value){return ByteBuffer.allocate(16).putLong(value.getMostSignificantBits()).putLong(value.getLeastSignificantBits()).array();}
    private static UUID uuid(byte[] bytes){var buffer=ByteBuffer.wrap(bytes);return new UUID(buffer.getLong(),buffer.getLong());}
}
