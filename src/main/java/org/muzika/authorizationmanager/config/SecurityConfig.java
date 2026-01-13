package org.muzika.authorizationmanager.config;

import org.muzika.authorizationmanager.filters.JwtAuthenticationFilter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.http.HttpMethod;

import java.util.Arrays;
import java.util.List;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtAuthenticationFilter;
    private final Environment environment;

    public SecurityConfig(JwtAuthenticationFilter jwtAuthenticationFilter, Environment environment) {
        this.jwtAuthenticationFilter = jwtAuthenticationFilter;
        this.environment = environment;
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuration = new CorsConfiguration();
        // Allow all origins - works with allowCredentials(false) for JWT tokens
        configuration.setAllowedOrigins(Arrays.asList("*"));
        configuration.setAllowedMethods(Arrays.asList("GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH", "HEAD"));
        configuration.setAllowedHeaders(Arrays.asList("*"));
        configuration.setExposedHeaders(Arrays.asList("*"));
        configuration.setAllowCredentials(false); // JWT tokens don't need CORS credentials (not cookies)
        configuration.setMaxAge(3600L);
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", configuration);
        return source;
    }

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        boolean isK8sProfile = Arrays.asList(environment.getActiveProfiles()).contains("k8s");
        
        http
            .csrf(csrf -> csrf.disable()) // Completely disable CSRF (stateless JWT API)
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> {
                // Allow OPTIONS requests (CORS preflight) without authentication
                auth.requestMatchers(HttpMethod.OPTIONS, "/**").permitAll();
                // Allow health check endpoints without authentication (for Load Balancer and ingress)
                auth.requestMatchers("/", "/health", "/actuator/health", "/actuator/**").permitAll();
                // Allow public registration and login endpoints (support both direct and /api/auth prefixed paths)
                // Explicitly allow POST for registration and login
                auth.requestMatchers(HttpMethod.POST, "/user", "/login", "/api/auth/user", "/api/auth/login").permitAll();
                auth.requestMatchers("/user", "/login", "/api/auth/user", "/api/auth/login").permitAll();
                // Allow Swagger UI endpoints without authentication on local profile (not k8s)
                if (!isK8sProfile) {
                    auth.requestMatchers("/swagger-ui.html", "/swagger-ui/**", 
                                        "/v3/api-docs", "/v3/api-docs/**", 
                                        "/api-docs", "/api-docs/**").permitAll();
                }
                // All other requests require authentication
                auth.anyRequest().authenticated();
            })
            .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);
        
        return http.build();
    }
}

