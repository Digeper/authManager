package org.muzika.authorizationmanager;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

@SpringBootApplication
@EnableJpaRepositories
public class AuthorizationManagerApplication {

    public static void main(String[] args) {
        SpringApplication.run(AuthorizationManagerApplication.class, args);
    }
}
