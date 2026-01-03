package org.muzika.authorizationmanager.dto;

import lombok.Data;

import java.util.UUID;

@Data
public class LoginResponse {
    private String token;
    private UUID userId;
    private String username;
    private String email;
}

