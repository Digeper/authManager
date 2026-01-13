package org.muzika.authorizationmanager.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Data;

import java.time.LocalDateTime;
import java.util.UUID;

@Data
@Schema(description = "User information response (without password)")
public class UserResponse {
    @Schema(description = "User UUID", example = "550e8400-e29b-41d4-a716-446655440000", required = true)
    private UUID id;
    
    @Schema(description = "Username", example = "johndoe", required = true)
    private String username;
    
    @Schema(description = "User email", example = "john.doe@example.com", format = "email")
    private String email;
    
    @Schema(description = "User creation timestamp", example = "2024-01-01T12:00:00Z", required = true)
    private LocalDateTime createdAt;
    
    @Schema(description = "User last update timestamp", example = "2024-01-15T14:30:00Z", required = true)
    private LocalDateTime updatedAt;
}

