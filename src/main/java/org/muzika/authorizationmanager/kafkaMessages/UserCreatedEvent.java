package org.muzika.authorizationmanager.kafkaMessages;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class UserCreatedEvent {
    private String username;
}

