package com.ksh321.songrecord.api.playback;

import java.util.Map;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@Profile("!bootstrap")
@ConditionalOnProperty(name="songrecord.storage.enabled", havingValue="true")
@RequestMapping("/v1")
public final class PlaybackController {
    private final PlaybackUrls urls;
    public PlaybackController(PlaybackUrls urls) { this.urls = urls; }
    @PostMapping("/recordings/{id}/playback-url")
    public ResponseEntity<Map<String,Object>> issue(
            @RequestHeader(value="Authorization", required=false) String auth,
            @RequestHeader(value="X-Device-Id", required=false) String device,
            @PathVariable("id") UUID id) {
        return ResponseEntity.ok().header("Cache-Control", "no-store")
                .body(urls.issue(auth, device, id));
    }
}
