package org.muzika.authorizationmanager.controllers;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.Map;

@RestController
@Tag(name = "Health", description = "Health check endpoints")
public class HealthController {

    @GetMapping("/")
    @Operation(
        summary = "Health check",
        description = "Check if the AuthorizationManager service is running"
    )
    @ApiResponse(
        responseCode = "200",
        description = "Service is UP",
        content = @Content(schema = @Schema(implementation = Map.class))
    )
    public ResponseEntity<Map<String, String>> health() {
        Map<String, String> response = new HashMap<>();
        response.put("status", "UP");
        response.put("service", "AuthorizationManager");
        return ResponseEntity.ok(response);
    }

    @GetMapping("/health")
    @Operation(
        summary = "Health check",
        description = "Check if the AuthorizationManager service is running"
    )
    @ApiResponse(
        responseCode = "200",
        description = "Service is UP",
        content = @Content(schema = @Schema(implementation = Map.class))
    )
    public ResponseEntity<Map<String, String>> healthCheck() {
        Map<String, String> response = new HashMap<>();
        response.put("status", "UP");
        response.put("service", "AuthorizationManager");
        return ResponseEntity.ok(response);
    }
}
