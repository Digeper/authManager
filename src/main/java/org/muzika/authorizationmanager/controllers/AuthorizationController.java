package org.muzika.authorizationmanager.controllers;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.muzika.authorizationmanager.dto.*;
import org.muzika.authorizationmanager.entities.User;
import org.muzika.authorizationmanager.services.AuthorizationService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Optional;
import java.util.UUID;

@RestController
@CrossOrigin(origins = "*", allowedHeaders = "*", methods = {RequestMethod.GET, RequestMethod.POST, RequestMethod.PUT, RequestMethod.DELETE, RequestMethod.OPTIONS, RequestMethod.PATCH})
@Tag(name = "Authorization", description = "User authentication and management endpoints")
public class AuthorizationController {

    private final AuthorizationService authorizationService;

    public AuthorizationController(AuthorizationService authorizationService) {
        this.authorizationService = authorizationService;
    }

    @PostMapping({"/user", "/api/auth/user"})
    @Operation(
        summary = "Create new user",
        description = "Create a new user account with username, password, and optional email"
    )
    @ApiResponses(value = {
        @ApiResponse(
            responseCode = "201",
            description = "User created successfully",
            content = @Content(schema = @Schema(implementation = UserResponse.class))
        ),
        @ApiResponse(
            responseCode = "400",
            description = "Bad request (validation error, missing required fields, or invalid email format)"
        ),
        @ApiResponse(
            responseCode = "409",
            description = "Conflict (username already exists)"
        ),
        @ApiResponse(
            responseCode = "500",
            description = "Internal server error"
        )
    })
    public ResponseEntity<UserResponse> createUser(
        @Parameter(description = "User creation data", required = true)
        @RequestBody CreateUserRequest request) {
        User user = authorizationService.createUser(
            request.getUsername(),
            request.getPassword(),
            request.getEmail()
        );

        UserResponse response = convertToResponse(user);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @PostMapping({"/login", "/api/auth/login"})
    @Operation(
        summary = "User login",
        description = "Authenticate user with username and password, returns JWT token"
    )
    @ApiResponses(value = {
        @ApiResponse(
            responseCode = "200",
            description = "Login successful",
            content = @Content(schema = @Schema(implementation = LoginResponse.class))
        ),
        @ApiResponse(
            responseCode = "401",
            description = "Unauthorized (invalid credentials)"
        ),
        @ApiResponse(
            responseCode = "500",
            description = "Internal server error"
        )
    })
    public ResponseEntity<LoginResponse> login(
        @Parameter(description = "Login credentials", required = true)
        @RequestBody LoginRequest request) {
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
    @Operation(
        summary = "Delete user",
        description = "Delete a user account by UUID"
    )
    @ApiResponses(value = {
        @ApiResponse(
            responseCode = "204",
            description = "User deleted successfully (No Content)"
        ),
        @ApiResponse(
            responseCode = "404",
            description = "User not found"
        ),
        @ApiResponse(
            responseCode = "500",
            description = "Internal server error"
        )
    })
    public ResponseEntity<Void> deleteUser(
        @Parameter(description = "User UUID", required = true, example = "550e8400-e29b-41d4-a716-446655440000")
        @PathVariable UUID id) {
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

