package org.muzika.authorizationmanager.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Data;

@Data
@Schema(description = "Login credentials")
public class LoginRequest {
    @Schema(description = "Username", example = "johndoe", required = true)
    private String username;
    
    @Schema(description = "Password", example = "securepassword123", required = true, format = "password")
    private String password;
}

