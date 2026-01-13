package org.muzika.authorizationmanager.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Data;

import java.util.UUID;

@Data
@Schema(description = "Login response with JWT token and user information")
public class LoginResponse {
    @Schema(description = "JWT authentication token", example = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...", required = true)
    private String token;
    
    @Schema(description = "User UUID", example = "550e8400-e29b-41d4-a716-446655440000", required = true)
    private UUID userId;
    
    @Schema(description = "Username", example = "johndoe", required = true)
    private String username;
    
    @Schema(description = "User email", example = "john.doe@example.com", format = "email", required = true)
    private String email;
}

