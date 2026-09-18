FROM php:8.3-cli AS php_dependencies

RUN apt-get update && apt-get install -y --no-install-recommends libicu-dev libonig-dev libpng-dev libpq-dev libxml2-dev libzip-dev unzip \
    && docker-php-ext-configure gd \
    && docker-php-ext-install bcmath dom gd intl mbstring pdo_pgsql zip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app

COPY composer.json composer.lock ./

RUN composer install --no-dev --prefer-dist --no-interaction --no-progress --no-scripts --optimize-autoloader

FROM node:22-alpine AS frontend_assets

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci

COPY resources ./resources
COPY public ./public
COPY vite.config.js tailwind.config.js postcss.config.js ./

RUN npm run build

FROM php:8.3-apache

RUN apt-get update && apt-get install -y --no-install-recommends libicu-dev libonig-dev libpq-dev libxml2-dev libzip-dev \
    && docker-php-ext-install bcmath dom intl mbstring pdo_pgsql zip \
    && a2enmod rewrite \
    && sed -ri 's!/var/www/html!/var/www/html/public!g; s/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf /etc/apache2/sites-available/000-default.conf \
    && sed -ri 's/Listen 80/Listen 10000/' /etc/apache2/ports.conf \
    && sed -ri 's/:80>/:10000>/' /etc/apache2/sites-available/000-default.conf \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

COPY . .
COPY --from=php_dependencies /app/vendor ./vendor
COPY --from=frontend_assets /app/public/build ./public/build

RUN mkdir -p storage/framework/cache storage/framework/sessions storage/framework/views storage/logs bootstrap/cache \
    && php artisan package:discover --ansi \
    && chown -R www-data:www-data storage bootstrap/cache

EXPOSE 10000

CMD ["sh", "-c", "php artisan migrate --force && apache2-foreground"]
