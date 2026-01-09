package org.muzika.authorizationmanager;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

import java.io.FileWriter;
import java.io.IOException;
import java.io.PrintWriter;

@SpringBootApplication
@EnableJpaRepositories
public class AuthorizationManagerApplication {

    private static final String LOG_PATH = "/Users/macabc/IdeaProjects/muzika/.cursor/debug.log";

    // #region agent log
    private static void logDebug(String hypothesisId, String message, String data) {
        String logEntry = String.format(
            "{\"sessionId\":\"debug-session\",\"runId\":\"startup\",\"hypothesisId\":\"%s\",\"location\":\"AuthorizationManagerApplication\",\"message\":\"%s\",\"data\":%s,\"timestamp\":%d}%n",
            hypothesisId, message.replace("\"", "\\\""), data != null ? data : "{}", System.currentTimeMillis()
        );
        // Write to file (for local debugging)
        try {
            try (FileWriter fw = new FileWriter(LOG_PATH, true);
                 PrintWriter pw = new PrintWriter(fw)) {
                pw.print(logEntry);
            }
        } catch (IOException e) {
            // Silently fail if log file cannot be written
        }
        // Also write to stdout (for Kubernetes pod logs)
        System.out.print(logEntry);
    }
    // #endregion agent log

    public static void main(String[] args) {
        // #region agent log
        logDebug("H1,H2,H3,H4", "Application main method started", "{\"argsCount\":" + args.length + "}");
        String postgresUrl = System.getenv("POSTGRES_URL");
        String postgresUsername = System.getenv("POSTGRES_USERNAME");
        String postgresPassword = System.getenv("POSTGRES_PASSWORD");
        boolean hasPostgresUrl = postgresUrl != null && !postgresUrl.isEmpty();
        boolean hasPostgresUsername = postgresUsername != null && !postgresUsername.isEmpty();
        boolean hasPostgresPassword = postgresPassword != null && !postgresPassword.isEmpty();
        String urlPreview = hasPostgresUrl ? (postgresUrl.length() > 50 ? postgresUrl.substring(0, 50) + "..." : postgresUrl) : "null";
        logDebug("H1", "Environment variables check in main", String.format(
            "{\"hasPostgresUrl\":%s,\"hasPostgresUsername\":%s,\"hasPostgresPassword\":%s,\"urlPreview\":\"%s\"}",
            hasPostgresUrl, hasPostgresUsername, hasPostgresPassword, urlPreview.replace("\"", "\\\"")
        ));
        // #endregion agent log
        
        try {
            // #region agent log
            logDebug("H1,H2,H3,H4", "Calling SpringApplication.run", "{}");
            // #endregion agent log
            SpringApplication.run(AuthorizationManagerApplication.class, args);
            // #region agent log
            logDebug("H1,H2,H3,H4", "SpringApplication.run completed successfully", "{}");
            // #endregion agent log
        } catch (Exception e) {
            // #region agent log
            logDebug("H4", "Application startup failed with exception", String.format("{\"exception\":\"%s\",\"message\":\"%s\"}", e.getClass().getName(), e.getMessage().replace("\"", "\\\"")));
            // #endregion agent log
            throw e;
        }
    }
}
