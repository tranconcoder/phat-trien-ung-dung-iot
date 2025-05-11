USE `app_db`;

-- Insert fake data for car_model
INSERT INTO `car_model` (`car_name`, `car_weight`, `car_price`, `car_image`, `car_description`) VALUES
('Toyota Camry', 1500, 25000.00, 'camry.jpg', 'A reliable midsize sedan with excellent fuel economy'),
('Honda Civic', 1300, 22000.00, 'civic.jpg', 'Compact car known for its reliability and efficiency'),
('Ford F-150', 2200, 35000.00, 'f150.jpg', 'America\'s best-selling pickup truck with powerful engine options'),
('BMW 3 Series', 1600, 42000.00, 'bmw3.jpg', 'Luxury compact sedan with sporty handling and premium features'),
('Tesla Model 3', 1800, 48000.00, 'tesla3.jpg', 'Popular electric sedan with impressive range and technology'),
('Volkswagen Golf', 1400, 24000.00, 'golf.jpg', 'Compact hatchback with refined interior and smooth driving experience'),
('Audi A4', 1700, 40000.00, 'audia4.jpg', 'Luxury sedan with sophisticated design and advanced technology'),
('Mercedes-Benz C-Class', 1700, 45000.00, 'cclass.jpg', 'Premium compact sedan with elegant styling and comfort');

-- Insert fake data for car_production
INSERT INTO `car_production` (`car_model_id`, `car_production_year`, `car_production_country`) VALUES
(1, 2022, 'Japan'),
(1, 2023, 'USA'),
(2, 2021, 'Japan'),
(2, 2022, 'Canada'),
(3, 2022, 'USA'),
(3, 2023, 'Mexico'),
(4, 2022, 'Germany'),
(5, 2023, 'USA'),
(6, 2021, 'Germany'),
(6, 2022, 'Mexico'),
(7, 2022, 'Germany'),
(8, 2023, 'Germany');
