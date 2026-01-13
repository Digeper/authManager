package org.muzika.authorizationmanager.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.Data;

@Data
@Schema(description = "Request to create a new user account")
public class CreateUserRequest {
    @Schema(description = "Username (alphanumeric, 3-20 characters)", example = "johndoe", required = true)
    private String username;
    
    @Schema(description = "Password (minimum 6 characters)", example = "securepassword123", required = true, format = "password")
    private String password;
    
    @Schema(description = "Email address (optional)", example = "john.doe@example.com", format = "email")
    private String email;
}

