CREATE DATABASE IF NOT EXISTS analytics2;
CREATE USER app_user IDENTIFIED BY 'StrongAppUserPass456!';
GRANT ALL ON analytics.* TO app_user;
SHOW GRANTS FOR app_user;
