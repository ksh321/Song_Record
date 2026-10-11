package com.ksh321.songrecord.api.auth;
import java.util.*;
import org.junit.jupiter.api.*;
import static org.assertj.core.api.Assertions.*;
import static com.ksh321.songrecord.api.songs.SongQueryKeys.*;
class TrashPlaylistRestorationTests {
    final TrashRestorationTests r=new TrashRestorationTests();
    @BeforeEach void open()throws Exception{r.open();}
    @AfterEach void close()throws Exception{r.close();}
    @Test void restoreAppendsAndPreservesActivePositionsAndReplay()throws Exception{
        var f=r.f;String batch=r.batch("SONG_ONLY");UUID song=UUID.randomUUID(),item=UUID.randomUUID();
        f.s.id=song;assertThat(f.s.postBody(UUID.randomUUID().toString(),f.s.body("").replace("valid","second")).getStatus()).isEqualTo(201);
        f.f.jdbc.update("INSERT INTO playlist_item(id,user_id,playlist_id,song_id,entry_key,position,created_at,updated_at) VALUES(?,?,?,?,?,20,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",bytes(item),bytes(f.owner()),bytes(f.parent),bytes(song),"TJ:990002");
        String op=UUID.randomUUID().toString();var reply=r.restore(batch,op,1,null);assertThat(reply.getStatus()).isEqualTo(200);assertThat(reply.getContentAsString()).contains("PLAYLIST_ITEM");
        assertThat(f.f.jdbc.queryForObject("SELECT position FROM playlist_item WHERE id=?",Long.class,bytes(f.item))).isEqualTo(21);
        assertThat(f.f.jdbc.queryForObject("SELECT position FROM playlist_item WHERE id=?",Long.class,bytes(item))).isEqualTo(20);
        assertThat(f.f.jdbc.queryForObject("SELECT hidden_by_batch_id FROM playlist_item WHERE id=?",byte[].class,bytes(f.item))).isNull();
        assertThat(r.restore(batch,op,1,null).getContentAsString()).isEqualTo(reply.getContentAsString());assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM playlist_item",Integer.class)).isEqualTo(2);
    }
    @Test void alreadyActiveEntryKeepsItsPosition()throws Exception{
        var f=r.f;String batch=r.batch("SONG_ONLY");f.f.jdbc.update("UPDATE playlist_item SET hidden_by_batch_id=NULL,position=13 WHERE id=?",bytes(f.item));
        var reply=r.restore(batch,UUID.randomUUID().toString(),1,null);assertThat(reply.getStatus()).isEqualTo(200);assertThat(reply.getContentAsString()).contains("STATE_CHANGED");assertThat(f.f.jdbc.queryForObject("SELECT position FROM playlist_item",Long.class)).isEqualTo(13);
    }
    @Test void deletedParentIsNotRecreated()throws Exception{
        var f=r.f;String batch=r.batch("SONG_ONLY");f.f.jdbc.update("UPDATE playlist SET deleted_at=CURRENT_TIMESTAMP WHERE id=?",bytes(f.parent));
        var reply=r.restore(batch,UUID.randomUUID().toString(),1,null);assertThat(reply.getStatus()).isEqualTo(200);assertThat(reply.getContentAsString()).contains("PARENT_UNAVAILABLE");assertThat(f.f.jdbc.queryForObject("SELECT hidden_by_batch_id FROM playlist_item",byte[].class)).isNotNull();assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM playlist",Integer.class)).isEqualTo(1);assertThat(f.f.jdbc.queryForObject("SELECT deleted_at FROM playlist",java.sql.Timestamp.class)).isNotNull();
    }
    @Test void positionOverflowRollsBackConnectedSongAndRecordingRestoration()throws Exception{
        var f=r.f;String batch=r.batch("SONG_ONLY");UUID original=f.s.id;f.s.id=UUID.randomUUID();assertThat(f.s.postBody(UUID.randomUUID().toString(),f.s.body("").replace("valid","second")).getStatus()).isEqualTo(201);
        f.f.jdbc.update("INSERT INTO playlist_item(id,user_id,playlist_id,song_id,entry_key,position,created_at,updated_at) VALUES(?,?,?,?,?,?,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",bytes(UUID.randomUUID()),bytes(f.owner()),bytes(f.parent),bytes(f.s.id),"TJ:990002",Long.MAX_VALUE);
        var reply=r.restore(batch,UUID.randomUUID().toString(),1,null);assertThat(reply.getStatus()).isEqualTo(409);assertThat(reply.getContentAsString()).contains("PLAYLIST_POSITION_LIMIT");
        assertThat(f.f.jdbc.queryForObject("SELECT lifecycle_state FROM song WHERE id=?",String.class,bytes(original))).isEqualTo("TRASHED");assertThat(f.f.jdbc.queryForObject("SELECT song_id FROM recording",byte[].class)).isNull();assertThat(f.f.jdbc.queryForObject("SELECT hidden_by_batch_id FROM playlist_item WHERE id=?",byte[].class,bytes(f.item))).isNotNull();assertThat(f.f.jdbc.queryForObject("SELECT COUNT(*) FROM deletion_batch_work",Integer.class)).isZero();
    }
}
