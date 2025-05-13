// Constants
const MQTT_HOST = "wss://fd66ecb3.ala.asia-southeast1.emqxsl.com:8084/mqtt"; // WebSocket secure URL
const MQTT_USERNAME = "trancon2";
const MQTT_PASSWORD = "123";
const MQTT_TOPIC = "/metrics"; // Topic to subscribe to
const DEFAULT_LAT = 10.8231; // Ho Chi Minh City coordinates
const DEFAULT_LNG = 106.6297;
const DEFAULT_ZOOM = 13;

// Globals
let map;
let mqttClient;
let carMarkers = {};
let cars = {};
let selectedCarId = null;
let centerOnSelect = true;
let isConnected = false;
let lastLocationUpdate = {};

// Initialize the map and MQTT connection
document.addEventListener("DOMContentLoaded", () => {
  // Initialize the map
  initMap();

  // Initialize MQTT connection
  initMQTT();

  // Setup event listeners
  setupEventListeners();

  // Initial simulated car data (while waiting for real data)
  setupSimulatedData();
});

// Initialize Leaflet map
function initMap() {
  // Create the map instance
  map = L.map("map").setView([DEFAULT_LAT, DEFAULT_LNG], DEFAULT_ZOOM);

  // Add the tile layer (OpenStreetMap)
  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    attribution:
      '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    maxZoom: 19,
  }).addTo(map);

  // Add a scale control
  L.control.scale().addTo(map);
}

// Initialize MQTT connection
function initMQTT() {
  updateMqttStatus("connecting");

  // Random client ID to prevent collisions
  const clientId = "webmap_" + Math.random().toString(16).substr(2, 8);

  // Connect to MQTT broker
  mqttClient = mqtt.connect(MQTT_HOST, {
    clientId: clientId,
    username: MQTT_USERNAME,
    password: MQTT_PASSWORD,
    clean: true,
    reconnectPeriod: 5000, // Try to reconnect every 5 seconds
    connectTimeout: 30000, // 30 seconds timeout
  });

  // Set up MQTT event handlers
  mqttClient.on("connect", () => {
    console.log("Connected to MQTT broker");
    updateMqttStatus("connected");
    isConnected = true;

    // Subscribe to the metrics topic
    mqttClient.subscribe(MQTT_TOPIC, (err) => {
      if (!err) {
        console.log(`Subscribed to ${MQTT_TOPIC}`);
      } else {
        console.error("Subscription error:", err);
      }
    });
  });

  mqttClient.on("message", (topic, message) => {
    // Process the incoming message
    try {
      const data = JSON.parse(message.toString());
      processCarData(data);
    } catch (error) {
      console.error("Error processing MQTT message:", error);
    }
  });

  mqttClient.on("offline", () => {
    console.log("MQTT client is offline");
    updateMqttStatus("disconnected");
    isConnected = false;
  });

  mqttClient.on("reconnect", () => {
    console.log("MQTT client is reconnecting");
    updateMqttStatus("connecting");
  });

  mqttClient.on("error", (error) => {
    console.error("MQTT error:", error);
    updateMqttStatus("disconnected");
  });
}

// Process incoming car data from MQTT
function processCarData(data) {
  // For real applications, the message would include car ID and location data
  // Since the car-board.ino doesn't include location data, we need to simulate it

  // In a real application, the car would send its ID and GPS coordinates
  // Here we're assuming the data comes with a unique identifier for the car
  const carId = data.carId || "car-001"; // Default to car-001 if no ID provided

  // Check if this is a new car
  if (!cars[carId]) {
    // Create a new car entry with simulated location near HCMC
    cars[carId] = {
      id: carId,
      name: `Xe ${Object.keys(cars).length + 1}`,
      plate: `51A-${Math.floor(10000 + Math.random() * 90000)}`,
      position: simulatePosition(),
      temperature: data.temperature || 0,
      humidity: data.humidity || 0,
      battery: data.battery || 0,
      speed: data.speed || 0,
      lastUpdate: new Date(),
      status: "active",
    };

    // Add to the car list
    addCarToList(cars[carId]);

    // Add marker to the map
    addCarMarker(cars[carId]);
  } else {
    // Update existing car data
    const car = cars[carId];
    car.temperature = data.temperature || car.temperature;
    car.humidity = data.humidity || car.humidity;
    car.battery = data.battery || car.battery;
    car.speed = data.speed || car.speed;
    car.lastUpdate = new Date();

    // Update car marker position - simulate movement if real GPS not available
    // Only update position every few updates to make movement look natural
    if (
      !lastLocationUpdate[carId] ||
      new Date() - lastLocationUpdate[carId] > 10000
    ) {
      // Simulate small movement based on the reported speed
      simulateMovement(car);
      lastLocationUpdate[carId] = new Date();
    }

    // Update the marker position
    updateCarMarker(car);

    // Update the car list item
    updateCarListItem(car);

    // Update details if this car is selected
    if (selectedCarId === carId) {
      showCarDetails(car);
    }
  }
}

// Simulate a position near Ho Chi Minh City
function simulatePosition() {
  // Random position within ~5km of the center of HCMC
  const lat = DEFAULT_LAT + (Math.random() - 0.5) * 0.05;
  const lng = DEFAULT_LNG + (Math.random() - 0.5) * 0.05;
  return [lat, lng];
}

// Simulate movement based on car speed
function simulateMovement(car) {
  // Only move if speed > 0
  if (car.speed > 0) {
    // Calculate movement distance based on speed
    // Higher speed = larger movement
    const factor = car.speed / 100; // Scale factor based on speed
    const maxDelta = 0.002 * factor; // Maximum ~200m at 100km/h

    // Random direction with slight bias towards previous direction
    const lat = car.position[0] + (Math.random() - 0.5) * maxDelta;
    const lng = car.position[1] + (Math.random() - 0.5) * maxDelta;

    car.position = [lat, lng];
  }
}

// Add a car marker to the map
function addCarMarker(car) {
  // Create a custom icon
  const carIcon = L.divIcon({
    className: "car-marker",
    html: `<div class="car-marker-icon"><i class="fas fa-car"></i></div>`,
    iconSize: [30, 30],
    iconAnchor: [15, 15],
  });

  // Create the marker
  const marker = L.marker(car.position, { icon: carIcon })
    .addTo(map)
    .bindPopup(createCarPopupContent(car));

  // Add click handler to the marker
  marker.on("click", () => {
    selectCar(car.id);
  });

  // Store the marker reference
  carMarkers[car.id] = marker;
}

// Update a car marker on the map
function updateCarMarker(car) {
  const marker = carMarkers[car.id];
  if (marker) {
    // Update marker position
    marker.setLatLng(car.position);

    // Update popup content
    marker.getPopup().setContent(createCarPopupContent(car));

    // If selected car and center option is enabled, center the map on it
    if (selectedCarId === car.id && centerOnSelect) {
      map.panTo(car.position);
    }
  }
}

// Create popup content for a car marker
function createCarPopupContent(car) {
  return `
    <div class="car-popup">
      <div class="car-popup-name">${car.name}</div>
      <div class="car-popup-data">
        <div>Biển số: ${car.plate}</div>
        <div>Nhiệt độ: ${car.temperature.toFixed(1)}°C</div>
        <div>Tốc độ: ${car.speed.toFixed(1)} km/h</div>
        <div>Pin: ${car.battery}%</div>
      </div>
      <a href="#" class="car-popup-link" onclick="selectCar('${
        car.id
      }')">Xem chi tiết</a>
    </div>
  `;
}

// Add a car to the list sidebar
function addCarToList(car) {
  const carListContainer = document.getElementById("car-list-container");
  const template = document.getElementById("car-item-template");

  // Clone the template
  const carItem = template.content.cloneNode(true);

  // Set the car data
  carItem.querySelector(".car-item").dataset.id = car.id;
  carItem.querySelector(".car-name").textContent = car.name;
  carItem.querySelector(".car-plate").textContent = car.plate;

  // Set the status
  const statusElem = carItem.querySelector(".car-status");
  statusElem.textContent =
    car.status === "active" ? "Hoạt động" : "Không hoạt động";
  statusElem.classList.add(car.status);

  // Add click handler
  carItem.querySelector(".car-item").addEventListener("click", () => {
    selectCar(car.id);
  });

  // Add to the list
  carListContainer.appendChild(carItem);
}

// Update a car item in the list
function updateCarListItem(car) {
  const carItem = document.querySelector(`.car-item[data-id="${car.id}"]`);
  if (carItem) {
    // Update status if needed
    const newStatus = car.speed > 0 ? "active" : "inactive";
    if (car.status !== newStatus) {
      car.status = newStatus;
      const statusElem = carItem.querySelector(".car-status");
      statusElem.textContent =
        car.status === "active" ? "Hoạt động" : "Không hoạt động";
      statusElem.className = "car-status " + car.status;
    }
  }
}

// Select a car and show its details
function selectCar(carId) {
  // Update selection state
  selectedCarId = carId;

  // Update UI to show selection
  document.querySelectorAll(".car-item").forEach((item) => {
    item.classList.toggle("active", item.dataset.id === carId);
  });

  // Show car details
  const car = cars[carId];
  if (car) {
    showCarDetails(car);

    // Center map on selected car if option is enabled
    if (centerOnSelect) {
      map.panTo(car.position);

      // Open the popup
      const marker = carMarkers[car.id];
      if (marker) {
        marker.openPopup();
      }
    }
  }
}

// Show car details in the sidebar
function showCarDetails(car) {
  const detailsContainer = document.getElementById("car-details");
  const template = document.getElementById("car-details-template");

  // Clear previous content
  detailsContainer.innerHTML = "";

  // Clone the template
  const detailsContent = template.content.cloneNode(true);

  // Set the car data
  detailsContent.querySelector(".car-details-name").textContent = car.name;
  detailsContent.querySelector(".car-details-plate").textContent = car.plate;
  detailsContent.querySelector(
    ".temperature"
  ).textContent = `${car.temperature.toFixed(1)}°C`;
  detailsContent.querySelector(
    ".humidity"
  ).textContent = `${car.humidity.toFixed(1)}%`;
  detailsContent.querySelector(".battery").textContent = `${car.battery}%`;
  detailsContent.querySelector(".speed").textContent = `${car.speed.toFixed(
    1
  )} km/h`;
  detailsContent.querySelector(".last-update").textContent = formatLastUpdate(
    car.lastUpdate
  );

  // Add event handler for "Center on car" button
  detailsContent
    .querySelector(".center-on-car")
    .addEventListener("click", () => {
      centerOnCar(car.id);
    });

  // Add to the container
  detailsContainer.appendChild(detailsContent);
}

// Center the map on a specific car
function centerOnCar(carId) {
  const car = cars[carId];
  if (car) {
    map.setView(car.position, DEFAULT_ZOOM);

    // Open the popup
    const marker = carMarkers[car.id];
    if (marker) {
      marker.openPopup();
    }
  }
}

// Format the last update time
function formatLastUpdate(date) {
  // If less than a minute ago, show "just now"
  const now = new Date();
  const diffMs = now - date;

  if (diffMs < 60000) {
    return "vừa mới";
  } else if (diffMs < 3600000) {
    const minutes = Math.floor(diffMs / 60000);
    return `${minutes} phút trước`;
  } else if (diffMs < 86400000) {
    const hours = Math.floor(diffMs / 3600000);
    return `${hours} giờ trước`;
  } else {
    // Format as date
    return date.toLocaleString("vi-VN");
  }
}

// Set up event listeners for buttons and controls
function setupEventListeners() {
  // Center map button
  document.getElementById("center-map").addEventListener("click", () => {
    map.setView([DEFAULT_LAT, DEFAULT_LNG], DEFAULT_ZOOM);
  });

  // Refresh data button
  document.getElementById("refresh-data").addEventListener("click", () => {
    // In a real app, you might request updated data or clear/reset the view
    if (selectedCarId && carMarkers[selectedCarId]) {
      centerOnCar(selectedCarId);
    }
  });
}

// Update MQTT connection status in the UI
function updateMqttStatus(status) {
  const statusElement = document.getElementById("mqtt-connection-status");
  if (statusElement) {
    statusElement.className = status;

    switch (status) {
      case "connected":
        statusElement.textContent = "MQTT: Đã kết nối";
        break;
      case "disconnected":
        statusElement.textContent = "MQTT: Mất kết nối";
        break;
      case "connecting":
        statusElement.textContent = "MQTT: Đang kết nối...";
        break;
      default:
        statusElement.textContent = "MQTT: Trạng thái không xác định";
    }
  }
}

// Setup simulated data for initial display if no MQTT data is available
function setupSimulatedData() {
  setTimeout(() => {
    // If we don't have any cars yet from MQTT, add a simulated one
    if (Object.keys(cars).length === 0) {
      processCarData({
        carId: "car-sim-1",
        temperature: 28.5,
        humidity: 65,
        battery: 85,
        speed: 45,
      });

      // Add a second simulated car
      processCarData({
        carId: "car-sim-2",
        temperature: 27.2,
        humidity: 62,
        battery: 73,
        speed: 0,
      });

      // Select the first car
      selectCar("car-sim-1");
    }
  }, 3000); // Wait 3 seconds for real MQTT data before adding simulated data
}

// Simulate random updates to cars for testing when no MQTT data is available
function simulateUpdates() {
  // If not connected to MQTT, simulate data updates
  if (!isConnected) {
    Object.keys(cars).forEach((carId) => {
      // Simulate temperature changes
      const tempChange = (Math.random() - 0.5) * 2;
      const car = cars[carId];

      // Random updates to the values
      processCarData({
        carId: carId,
        temperature: car.temperature + tempChange,
        humidity: car.humidity + (Math.random() - 0.5) * 5,
        battery: Math.max(0, car.battery - Math.random() * 0.5), // Slowly drain battery
        speed:
          car.status === "active"
            ? Math.max(0, car.speed + (Math.random() - 0.4) * 10)
            : 0, // Adjust speed randomly
      });
    });
  }

  // Schedule next update
  setTimeout(simulateUpdates, 5000); // Update every 5 seconds
}

// Start simulating updates after a delay
setTimeout(simulateUpdates, 5000);

// Add to the global scope for use in inline HTML event handlers
window.selectCar = selectCar;
window.centerOnCar = centerOnCar;
