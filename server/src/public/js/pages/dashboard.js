/**
 * Dashboard page specific JavaScript
 */
document.addEventListener("DOMContentLoaded", function () {
  console.log("Dashboard page loaded");

  // Refresh button functionality
  const refreshButton = document.querySelector(
    ".dashboard-actions button:nth-child(2)"
  );
  if (refreshButton) {
    refreshButton.addEventListener("click", function () {
      console.log("Refreshing dashboard data...");
      // Simulate loading state
      this.textContent = "Đang tải...";
      this.disabled = true;

      // Simulate data refresh with timeout
      setTimeout(() => {
        console.log("Dashboard data refreshed");
        this.textContent = "Làm mới";
        this.disabled = false;

        // Show success notification
        showNotification("Dữ liệu đã được cập nhật", "success");
      }, 1500);
    });
  }

  // Settings button functionality
  const settingsButton = document.querySelector(
    ".dashboard-actions button:nth-child(1)"
  );
  if (settingsButton) {
    settingsButton.addEventListener("click", function () {
      console.log("Opening dashboard settings...");
      showNotification("Tính năng đang được phát triển", "info");
    });
  }

  // Camera item click events
  const cameraItems = document.querySelectorAll(".camera-item");
  cameraItems.forEach((item) => {
    item.addEventListener("click", function () {
      const cameraName = this.querySelector(".camera-preview").textContent;
      const cameraLocation = this.querySelector(".camera-info p").textContent;
      console.log(`Selected camera: ${cameraName} at ${cameraLocation}`);

      // Show info about the selected camera
      showNotification(`Đã chọn ${cameraName} tại ${cameraLocation}`, "info");
    });
  });

  // Incident view buttons
  const viewButtons = document.querySelectorAll(".incident-actions .btn");
  viewButtons.forEach((button) => {
    button.addEventListener("click", function (e) {
      // Prevent the click from bubbling up to parent elements
      e.stopPropagation();

      const incidentItem = this.closest(".incident-item");
      const incidentTitle = incidentItem.querySelector("h4").textContent;
      console.log(`Viewing incident: ${incidentTitle}`);

      // Show detailed info about the incident
      showNotification(`Đang xem chi tiết: ${incidentTitle}`, "info");
    });
  });

  /**
   * Show a notification message
   * @param {string} message - The message to display
   * @param {string} type - The type of notification (success, error, info)
   */
  function showNotification(message, type = "info") {
    // Check if notification container exists, create if not
    let notificationContainer = document.querySelector(
      ".notification-container"
    );
    if (!notificationContainer) {
      notificationContainer = document.createElement("div");
      notificationContainer.className = "notification-container";
      notificationContainer.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        z-index: 1000;
      `;
      document.body.appendChild(notificationContainer);
    }

    // Create notification element
    const notification = document.createElement("div");
    notification.className = `notification ${type}`;
    notification.textContent = message;

    // Style the notification
    notification.style.cssText = `
      padding: 12px 20px;
      margin-bottom: 10px;
      border-radius: 4px;
      color: white;
      box-shadow: 0 2px 5px rgba(0,0,0,0.2);
      opacity: 0;
      transform: translateX(50px);
      transition: all 0.3s ease;
    `;

    // Set background color based on type
    switch (type) {
      case "success":
        notification.style.backgroundColor = "#2ecc71";
        break;
      case "error":
        notification.style.backgroundColor = "#e74c3c";
        break;
      case "info":
      default:
        notification.style.backgroundColor = "#3498db";
    }

    // Add to container
    notificationContainer.appendChild(notification);

    // Trigger animation
    setTimeout(() => {
      notification.style.opacity = "1";
      notification.style.transform = "translateX(0)";
    }, 10);

    // Remove after delay
    setTimeout(() => {
      notification.style.opacity = "0";
      notification.style.transform = "translateX(50px)";

      // Remove from DOM after animation completes
      setTimeout(() => {
        notificationContainer.removeChild(notification);

        // Remove container if empty
        if (notificationContainer.children.length === 0) {
          document.body.removeChild(notificationContainer);
        }
      }, 300);
    }, 3000);
  }
});
