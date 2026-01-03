package org.muzika.authorizationmanager.dto;

import lombok.Data;

@Data
public class LoginRequest {
    private String username;
    private String password;
}

