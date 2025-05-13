document.addEventListener("DOMContentLoaded", () => {
  // Elements
  const carSelect = document.getElementById("car-select");
  const metricsChart = document.getElementById("metrics-chart");
  const metricButtons = document.querySelectorAll(".metric-btn");
  const timeButtons = document.querySelectorAll(".time-btn");
  const tempValue = document.getElementById("temp-value");
  const humidityValue = document.getElementById("humidity-value");
  const speedValue = document.getElementById("speed-value");
  const batteryValue = document.getElementById("battery-value");
  const lastUpdateTime = document.getElementById("last-update-time");
  const refreshBtn = document.getElementById("refresh-btn");

  // Chart state
  let currentChart = null;
  let selectedCarId = null;
  let selectedMetric = "temperature";
  let selectedPeriod = "24h";
  let carData = null;

  // Initialize Chart.js
  initChart();

  // Load cars
  loadCars();

  // Setup event listeners
  setupEventListeners();

  // Functions
  function initChart() {
    const ctx = metricsChart.getContext("2d");

    // Default empty chart
    currentChart = new Chart(ctx, {
      type: "line",
      data: {
        labels: [],
        datasets: [
          {
            label: "Temperature (°C)",
            data: [],
            borderColor: "rgb(255, 99, 132)",
            tension: 0.1,
            fill: false,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: {
            title: {
              display: true,
              text: "Time",
            },
          },
          y: {
            beginAtZero: false,
            title: {
              display: true,
              text: "Value",
            },
          },
        },
        plugins: {
          legend: {
            display: true,
            position: "top",
          },
          tooltip: {
            mode: "index",
            intersect: false,
          },
        },
      },
    });
  }

  async function loadCars() {
    try {
      // Clear select
      carSelect.innerHTML = '<option value="">Loading cars...</option>';

      // Fetch car list from API
      const response = await fetch("/api/cars");
      const result = await response.json();

      if (!result.success || !result.data || result.data.length === 0) {
        carSelect.innerHTML = '<option value="">No cars available</option>';
        return;
      }

      // Populate select
      carSelect.innerHTML = '<option value="">Select a car</option>';
      result.data.forEach((car) => {
        const option = document.createElement("option");
        option.value = car.carId;
        option.textContent = car.carId;
        carSelect.appendChild(option);
      });

      // Select first car if available
      if (result.data.length > 0) {
        selectedCarId = result.data[0].carId;
        carSelect.value = selectedCarId;
        loadCarData();
      }
    } catch (error) {
      console.error("Error loading cars:", error);
      carSelect.innerHTML = '<option value="">Error loading cars</option>';
    }
  }

  async function loadCarData() {
    if (!selectedCarId) return;

    try {
      // Show loading state
      setLoadingState(true);

      // Fetch latest data
      const latestResponse = await fetch(`/api/cars/${selectedCarId}/latest`);
      const latestResult = await latestResponse.json();

      if (latestResult.success && latestResult.data) {
        // Update the UI with the latest values
        updateLatestValues(latestResult.data);
      }

      // Fetch chart data
      const chartResponse = await fetch(
        `/api/cars/${selectedCarId}/chart?type=${selectedMetric}&period=${selectedPeriod}`
      );
      const chartResult = await chartResponse.json();

      if (chartResult.success && chartResult.data) {
        // Update the chart
        updateChart(chartResult.data);
      } else {
        // Show empty chart
        updateChart({
          labels: [],
          datasets: [
            {
              label: getMetricLabel(selectedMetric),
              data: [],
              borderColor: getMetricColor(selectedMetric),
              fill: false,
            },
          ],
        });
      }

      // Hide loading state
      setLoadingState(false);
    } catch (error) {
      console.error("Error loading car data:", error);
      setLoadingState(false);
    }
  }

  function updateChart(chartData) {
    if (!currentChart) return;

    // Update chart data
    currentChart.data = chartData;

    // Update options
    currentChart.options.scales.y.title.text = getMetricLabel(selectedMetric);

    // Refresh chart
    currentChart.update();
  }

  function updateLatestValues(data) {
    // Update values on the page
    if (data.temperature !== undefined) {
      tempValue.textContent = data.temperature.toFixed(1);
    }

    if (data.humidity !== undefined) {
      humidityValue.textContent = data.humidity.toFixed(1);
    }

    if (data.speed !== undefined) {
      speedValue.textContent = data.speed.toFixed(1);
    }

    if (data.battery !== undefined) {
      batteryValue.textContent = data.battery.toFixed(1);
    }

    // Update last update time
    const timestamp = data.timestamp ? new Date(data.timestamp) : new Date();
    lastUpdateTime.textContent = timestamp.toLocaleString();
  }

  function setLoadingState(isLoading) {
    if (isLoading) {
      metricsChart.classList.add("loading");
      refreshBtn.disabled = true;
    } else {
      metricsChart.classList.remove("loading");
      refreshBtn.disabled = false;
    }
  }

  function setupEventListeners() {
    // Car select change
    carSelect.addEventListener("change", () => {
      selectedCarId = carSelect.value;
      if (selectedCarId) {
        loadCarData();
      } else {
        // Clear UI if no car selected
        updateLatestValues({});
        updateChart({
          labels: [],
          datasets: [
            {
              label: getMetricLabel(selectedMetric),
              data: [],
              borderColor: getMetricColor(selectedMetric),
              fill: false,
            },
          ],
        });
      }
    });

    // Metric buttons
    metricButtons.forEach((button) => {
      button.addEventListener("click", () => {
        // Update active state
        metricButtons.forEach((btn) => btn.classList.remove("active"));
        button.classList.add("active");

        // Update selected metric
        selectedMetric = button.getAttribute("data-type");

        // Reload data
        if (selectedCarId) {
          loadCarData();
        }
      });
    });

    // Time period buttons
    timeButtons.forEach((button) => {
      button.addEventListener("click", () => {
        // Update active state
        timeButtons.forEach((btn) => btn.classList.remove("active"));
        button.classList.add("active");

        // Update selected period
        selectedPeriod = button.getAttribute("data-period");

        // Reload data
        if (selectedCarId) {
          loadCarData();
        }
      });
    });

    // Refresh button
    refreshBtn.addEventListener("click", () => {
      if (selectedCarId) {
        loadCarData();
      } else {
        loadCars();
      }
    });
  }

  function getMetricLabel(metric) {
    switch (metric) {
      case "temperature":
        return "Temperature (°C)";
      case "humidity":
        return "Humidity (%)";
      case "speed":
        return "Speed (km/h)";
      case "battery":
        return "Battery (%)";
      default:
        return "Value";
    }
  }

  function getMetricColor(metric) {
    switch (metric) {
      case "temperature":
        return "rgb(255, 99, 132)";
      case "humidity":
        return "rgb(54, 162, 235)";
      case "speed":
        return "rgb(153, 102, 255)";
      case "battery":
        return "rgb(75, 192, 192)";
      default:
        return "rgb(201, 203, 207)";
    }
  }
});
