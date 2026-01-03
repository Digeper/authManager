package org.muzika.authorizationmanager.services;

import org.muzika.authorizationmanager.entities.User;
import org.muzika.authorizationmanager.kafkaMessages.UserCreatedEvent;
import org.muzika.authorizationmanager.repository.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;
import java.util.UUID;

@Service
@Transactional
public class AuthorizationService {

    private final UserRepository userRepository;
    private final PasswordService passwordService;
    private final JwtService jwtService;
    private final KafkaProducerService kafkaProducerService;
    private static final String USER_CREATED_TOPIC = "user-created";

    public AuthorizationService(UserRepository userRepository, 
                           PasswordService passwordService,
                           JwtService jwtService,
                           KafkaProducerService kafkaProducerService) {
        this.userRepository = userRepository;
        this.passwordService = passwordService;
        this.jwtService = jwtService;
        this.kafkaProducerService = kafkaProducerService;
    }

    public User createUser(String username, String password, String email) {
        // Validate username uniqueness
        if (userRepository.existsByUsername(username)) {
            throw new IllegalArgumentException("Username already exists: " + username);
        }

        // Validate email uniqueness if provided
        if (email != null && !email.isEmpty() && userRepository.existsByEmail(email)) {
            throw new IllegalArgumentException("Email already exists: " + email);
        }

        // Validate username format (alphanumeric, 3-20 characters)
        if (!username.matches("^[a-zA-Z0-9]{3,20}$")) {
            throw new IllegalArgumentException("Username must be alphanumeric and 3-20 characters long");
        }

        // Validate password strength (minimum 6 characters)
        if (password == null || password.length() < 6) {
            throw new IllegalArgumentException("Password must be at least 6 characters long");
        }

        User user = new User();
        user.setUsername(username);
        user.setPassword(passwordService.hashPassword(password));
        user.setEmail(email);

        User savedUser = userRepository.save(user);

        // Send Kafka event for user creation
        UserCreatedEvent event = new UserCreatedEvent(savedUser.getUsername());
        kafkaProducerService.sendUserCreatedEvent(USER_CREATED_TOPIC, savedUser.getUsername(), event);

        return savedUser;
    }

    public String authenticateUser(String username, String password) {
        Optional<User> userOpt = userRepository.findByUsername(username);
        
        if (userOpt.isEmpty()) {
            throw new IllegalArgumentException("Invalid username or password");
        }

        User user = userOpt.get();
        
        if (!passwordService.verifyPassword(password, user.getPassword())) {
            throw new IllegalArgumentException("Invalid username or password");
        }

        return jwtService.generateToken(username);
    }

    public void deleteUser(UUID userId) {
        if (!userRepository.existsById(userId)) {
            throw new IllegalArgumentException("User not found with id: " + userId);
        }
        userRepository.deleteById(userId);
    }

    public Optional<User> getUserById(UUID userId) {
        return userRepository.findById(userId);
    }

    public Optional<User> getUserByUsername(String username) {
        return userRepository.findByUsername(username);
    }
}

