/**
 * Main JavaScript file for the Car Management System
 * Provides common functionality used across the application
 */

document.addEventListener("DOMContentLoaded", () => {
  // Initialize common UI elements
  initNavbar();

  // Global event listeners
  setupGlobalEventListeners();
});

/**
 * Initialize navbar functionality
 */
function initNavbar() {
  // Highlight active nav item based on current page
  const currentPath = window.location.pathname;
  const navLinks = document.querySelectorAll(".nav-link");

  navLinks.forEach((link) => {
    const href = link.getAttribute("href");
    if (
      href === currentPath ||
      (href !== "/" && currentPath.startsWith(href))
    ) {
      link.classList.add("active");
    }
  });
}

/**
 * Setup global event listeners
 */
function setupGlobalEventListeners() {
  // Add click event for any notification close buttons
  document.querySelectorAll(".notification .close").forEach((closeBtn) => {
    closeBtn.addEventListener("click", function () {
      const notification = this.closest(".notification");
      notification.classList.add("fade-out");

      setTimeout(() => {
        notification.remove();
      }, 300);
    });
  });
}

/**
 * Format a date string to locale format
 * @param {string} dateString - The date string to format
 * @param {boolean} includeTime - Whether to include time in the format
 * @returns {string} Formatted date string
 */
function formatDate(dateString, includeTime = false) {
  try {
    const date = new Date(dateString);
    const options = {
      year: "numeric",
      month: "short",
      day: "numeric",
      ...(includeTime && { hour: "2-digit", minute: "2-digit" }),
    };

    return date.toLocaleDateString("vi-VN", options);
  } catch (error) {
    console.error("Error formatting date:", error);
    return dateString;
  }
}

/**
 * Show a notification message
 * @param {string} message - The message to display
 * @param {string} type - The type of notification (success, error, warning, info)
 * @param {number} duration - How long to display the notification in ms (0 for no auto-hide)
 */
function showNotification(message, type = "info", duration = 5000) {
  // Create notification element
  const notification = document.createElement("div");
  notification.className = `notification notification-${type}`;

  notification.innerHTML = `
    <div class="notification-content">
      <i class="notification-icon fas fa-${getIconForType(type)}"></i>
      <span class="notification-message">${message}</span>
    </div>
    <button class="close">&times;</button>
  `;

  // Add to document
  const notificationsContainer = document.getElementById(
    "notifications-container"
  );
  if (notificationsContainer) {
    notificationsContainer.appendChild(notification);
  } else {
    // Create container if it doesn't exist
    const container = document.createElement("div");
    container.id = "notifications-container";
    container.appendChild(notification);
    document.body.appendChild(container);
  }

  // Setup auto-hide if duration > 0
  if (duration > 0) {
    setTimeout(() => {
      notification.classList.add("fade-out");
      setTimeout(() => notification.remove(), 300);
    }, duration);
  }

  // Add close button event
  notification.querySelector(".close").addEventListener("click", function () {
    notification.classList.add("fade-out");
    setTimeout(() => notification.remove(), 300);
  });
}

/**
 * Get appropriate icon for notification type
 * @param {string} type - Notification type
 * @returns {string} Icon name
 */
function getIconForType(type) {
  switch (type) {
    case "success":
      return "check-circle";
    case "error":
      return "exclamation-circle";
    case "warning":
      return "exclamation-triangle";
    case "info":
    default:
      return "info-circle";
  }
}

// Export common functions to global scope
window.formatDate = formatDate;
window.showNotification = showNotification;
