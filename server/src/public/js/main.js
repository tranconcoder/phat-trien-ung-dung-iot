// Main JavaScript file

document.addEventListener("DOMContentLoaded", function () {
  console.log("Document loaded");

  // Mobile menu toggle (if needed)
  const mobileMenuButton = document.querySelector(".mobile-menu-button");
  if (mobileMenuButton) {
    mobileMenuButton.addEventListener("click", function () {
      const navItems = document.querySelector(".nav-items");
      navItems.classList.toggle("show");
    });
  }

  // Form validation
  const forms = document.querySelectorAll("form[data-validate]");
  forms.forEach((form) => {
    form.addEventListener("submit", function (e) {
      const requiredFields = form.querySelectorAll("[required]");
      let isValid = true;

      requiredFields.forEach((field) => {
        if (!field.value.trim()) {
          isValid = false;
          // Add error class
          field.classList.add("is-invalid");
          // Create error message if not exists
          let errorMsg = field.parentNode.querySelector(".error-message");
          if (!errorMsg) {
            errorMsg = document.createElement("div");
            errorMsg.className = "error-message";
            errorMsg.textContent = "Trường này là bắt buộc";
            field.parentNode.appendChild(errorMsg);
          }
        } else {
          // Remove error class
          field.classList.remove("is-invalid");
          // Remove error message if exists
          const errorMsg = field.parentNode.querySelector(".error-message");
          if (errorMsg) {
            errorMsg.remove();
          }
        }
      });

      if (!isValid) {
        e.preventDefault();
      }
    });
  });

  // Add any other client-side functionality here
});
