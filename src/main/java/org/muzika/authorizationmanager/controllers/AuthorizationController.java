package org.muzika.authorizationmanager.controllers;

import org.muzika.authorizationmanager.dto.*;
import org.muzika.authorizationmanager.entities.User;
import org.muzika.authorizationmanager.services.AuthorizationService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Optional;
import java.util.UUID;

@RestController
public class AuthorizationController {

    private final AuthorizationService authorizationService;

    public AuthorizationController(AuthorizationService authorizationService) {
        this.authorizationService = authorizationService;
    }

    @PostMapping("/user")
    public ResponseEntity<UserResponse> createUser(@RequestBody CreateUserRequest request) {
        User user = authorizationService.createUser(
            request.getUsername(),
            request.getPassword(),
            request.getEmail()
        );

        UserResponse response = convertToResponse(user);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @PostMapping("/login")
    public ResponseEntity<LoginResponse> login(@RequestBody LoginRequest request) {
        String token = authorizationService.authenticateUser(
            request.getUsername(),
            request.getPassword()
        );

        Optional<User> userOpt = authorizationService.getUserByUsername(request.getUsername());

        if (userOpt.isEmpty()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        User user = userOpt.get();
        LoginResponse response = new LoginResponse();
        response.setToken(token);
        response.setUserId(user.getId());
        response.setUsername(user.getUsername());
        response.setEmail(user.getEmail());

        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/user/{id}")
    public ResponseEntity<Void> deleteUser(@PathVariable UUID id) {
        authorizationService.deleteUser(id);
        return ResponseEntity.noContent().build();
    }

    private UserResponse convertToResponse(User user) {
        UserResponse response = new UserResponse();
        response.setId(user.getId());
        response.setUsername(user.getUsername());
        response.setEmail(user.getEmail());
        response.setCreatedAt(user.getCreatedAt());
        response.setUpdatedAt(user.getUpdatedAt());
        return response;
    }
}

