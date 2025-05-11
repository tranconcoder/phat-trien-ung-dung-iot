#include "http_server.h"

static const char *TAG = "http_server";
static httpd_handle_t server = NULL;

#define NVS_NAMESPACE "websocket"
#define NVS_URI_KEY "uri"
#define DEFAULT_WS_URI "ws://192.168.1.225:8887/frontcam"

// HTML templates for the configuration page
static const char *html_header = "<!DOCTYPE html>"
                              "<html>"
                              "<head>"
                              "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
                              "<title>ESP32 Camera Security Gate - Config</title>"
                              "<style>"
                              "body { font-family: Arial, sans-serif; margin: 0; padding: 20px; line-height: 1.6; }"
                              "h1 { color: #0066cc; }"
                              ".container { max-width: 500px; margin: 0 auto; padding: 20px; border: 1px solid #ddd; border-radius: 5px; }"
                              "label { display: block; margin-bottom: 5px; font-weight: bold; }"
                              "input[type=text] { width: 100%; padding: 8px; margin-bottom: 15px; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box; }"
                              "button { background-color: #0066cc; color: white; border: none; padding: 10px 15px; border-radius: 4px; cursor: pointer; }"
                              "button:hover { background-color: #0052a3; }"
                              ".alert { padding: 10px; margin-bottom: 15px; border-radius: 4px; }"
                              ".success { background-color: #d4edda; color: #155724; }"
                              "</style>"
                              "</head>"
                              "<body>"
                              "<div class=\"container\">"
                              "<h1>Camera Security Gate Configuration</h1>";

static const char *html_footer = "</div>"
                              "</body>"
                              "</html>";

// Get the websocket URI from NVS
esp_err_t get_websocket_uri(char *uri_buffer, size_t buffer_size) {
    nvs_handle_t nvs_handle;
    esp_err_t err;

    // Open NVS
    err = nvs_open(NVS_NAMESPACE, NVS_READONLY, &nvs_handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Error opening NVS (%s)", esp_err_to_name(err));
        // If not found, use default URI
        snprintf(uri_buffer, buffer_size, "%s", DEFAULT_WS_URI);
        return err;
    }

    // Read the URI from NVS
    size_t required_size = 0;
    err = nvs_get_str(nvs_handle, NVS_URI_KEY, NULL, &required_size);
    if (err == ESP_OK) {
        if (required_size <= buffer_size) {
            err = nvs_get_str(nvs_handle, NVS_URI_KEY, uri_buffer, &required_size);
        } else {
            ESP_LOGE(TAG, "Buffer too small for URI");
            err = ESP_ERR_INVALID_SIZE;
        }
    } else {
        // If key doesn't exist, use default URI
        ESP_LOGI(TAG, "No saved URI found, using default");
        snprintf(uri_buffer, buffer_size, "%s", DEFAULT_WS_URI);
    }

    nvs_close(nvs_handle);
    return err;
}

// Save the websocket URI to NVS
esp_err_t save_websocket_uri(const char *uri) {
    nvs_handle_t nvs_handle;
    esp_err_t err;

    // Open NVS
    err = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs_handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Error opening NVS (%s)", esp_err_to_name(err));
        return err;
    }

    // Save the URI to NVS
    err = nvs_set_str(nvs_handle, NVS_URI_KEY, uri);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Error saving URI to NVS (%s)", esp_err_to_name(err));
        nvs_close(nvs_handle);
        return err;
    }

    // Commit changes
    err = nvs_commit(nvs_handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Error committing NVS changes (%s)", esp_err_to_name(err));
    }

    nvs_close(nvs_handle);
    return err;
}

// Handler for the root page
static esp_err_t root_get_handler(httpd_req_t *req) {
    char uri_buffer[128] = {0};
    get_websocket_uri(uri_buffer, sizeof(uri_buffer));

    // Send header
    httpd_resp_sendstr_chunk(req, html_header);

    // Send form with current URI
    char form_html[512];
    snprintf(form_html, sizeof(form_html),
             "<form action=\"/save\" method=\"post\">"
             "<div>"
             "<label for=\"uri\">WebSocket Server URI:</label>"
             "<input type=\"text\" id=\"uri\" name=\"uri\" value=\"%s\" placeholder=\"ws://server:port/path\">"
             "</div>"
             "<button type=\"submit\">Save Configuration</button>"
             "</form>",
             uri_buffer);

    httpd_resp_sendstr_chunk(req, form_html);
    
    // Send footer
    httpd_resp_sendstr_chunk(req, html_footer);
    httpd_resp_sendstr_chunk(req, NULL);
    
    return ESP_OK;
}

// Handler for saving the configuration
static esp_err_t save_post_handler(httpd_req_t *req) {
    char content[128];
    int ret, remaining = req->content_len;

    if (remaining > sizeof(content) - 1) {
        ESP_LOGE(TAG, "Content too long");
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "Content too long");
        return ESP_FAIL;
    }

    // Read POST data
    ret = httpd_req_recv(req, content, remaining);
    if (ret <= 0) {
        ESP_LOGE(TAG, "Failed to receive POST data");
        httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "Failed to receive POST data");
        return ESP_FAIL;
    }
    content[ret] = '\0';

    // Parse the URI from the form data (format: "uri=ws://...")
    char *uri_start = strstr(content, "uri=");
    if (!uri_start) {
        ESP_LOGE(TAG, "URI parameter not found");
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "URI parameter not found");
        return ESP_FAIL;
    }

    // Extract the URI value
    char uri[128];
    uri_start += 4; // Skip "uri="
    
    // URL decode the value
    int i = 0, j = 0;
    while (uri_start[i] && j < sizeof(uri) - 1) {
        if (uri_start[i] == '%' && i + 2 < ret) {
            // Handle URL encoding (e.g., %3A becomes :)
            char hex[3] = {uri_start[i+1], uri_start[i+2], 0};
            uri[j++] = strtol(hex, NULL, 16);
            i += 3;
        } else if (uri_start[i] == '+') {
            // Handle space encoding
            uri[j++] = ' ';
            i++;
        } else {
            uri[j++] = uri_start[i++];
        }
    }
    uri[j] = '\0';

    // Save the URI to NVS
    esp_err_t err = save_websocket_uri(uri);
    
    // Send response
    httpd_resp_sendstr_chunk(req, html_header);
    
    // Increase buffer size to 512 bytes to avoid truncation
    char response[512];
    if (err == ESP_OK) {
        snprintf(response, sizeof(response),
                 "<div class=\"alert success\">"
                 "<p>Configuration saved successfully!</p>"
                 "<p>WebSocket URI: %s</p>"
                 "</div>"
                 "<p><a href=\"/\">Back to configuration</a></p>",
                 uri);
    } else {
        snprintf(response, sizeof(response),
                 "<div class=\"alert error\">"
                 "<p>Error saving configuration: %s</p>"
                 "</div>"
                 "<p><a href=\"/\">Back to configuration</a></p>",
                 esp_err_to_name(err));
    }
    
    httpd_resp_sendstr_chunk(req, response);
    httpd_resp_sendstr_chunk(req, html_footer);
    httpd_resp_sendstr_chunk(req, NULL);
    
    return ESP_OK;
}

// Register URI handlers
static httpd_uri_t root = {
    .uri       = "/",
    .method    = HTTP_GET,
    .handler   = root_get_handler,
    .user_ctx  = NULL
};

static httpd_uri_t save_config = {
    .uri       = "/save",
    .method    = HTTP_POST,
    .handler   = save_post_handler,
    .user_ctx  = NULL
};

// Start the HTTP server
esp_err_t start_config_http_server(void) {
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.stack_size = 8192;
    
    // Start the HTTP server
    ESP_LOGI(TAG, "Starting config HTTP server on port %d", config.server_port);
    if (httpd_start(&server, &config) == ESP_OK) {
        // Register URI handlers
        httpd_register_uri_handler(server, &root);
        httpd_register_uri_handler(server, &save_config);
        return ESP_OK;
    }
    
    ESP_LOGE(TAG, "Failed to start config HTTP server");
    return ESP_FAIL;
} 