package org.muzika.authorizationmanager.dto;

import lombok.Data;

@Data
public class CreateUserRequest {
    private String username;
    private String password;
    private String email;
}

