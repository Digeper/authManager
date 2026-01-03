package org.muzika.authorizationmanager.services;

import org.muzika.authorizationmanager.kafkaMessages.UserCreatedEvent;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;

@Service
public class KafkaProducerService {

    private final Logger logger = LoggerFactory.getLogger(KafkaProducerService.class);

    @Autowired
    KafkaTemplate<String, UserCreatedEvent> userCreatedKafka;

    public void sendUserCreatedEvent(String topic, String username, UserCreatedEvent event) {
        var future = userCreatedKafka.send(topic, username, event);
        future.whenComplete((r, e) -> {
            if (e != null) {
                logger.error("Failed to send user created event: " + e.getMessage());
                future.completeExceptionally(e);
            } else {
                logger.info("User created event sent successfully: " + event.toString());
                future.complete(r);
            }
        });
    }
}

