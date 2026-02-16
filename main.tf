data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_vpc" "dev_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "dev-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.dev_vpc.id

  tags = {
    Name = "dev-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.dev_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

# Public subnets in 2 AZs
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.dev_vpc.id
  cidr_block              = var.public_subnet_cidrs[0]
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.dev_vpc.id
  cidr_block              = var.public_subnet_cidrs[1]
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-b"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Private subnets in 2 AZs (no NAT for now)
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.dev_vpc.id
  cidr_block        = var.private_subnet_cidrs[0]
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.dev_vpc.id
  cidr_block        = var.private_subnet_cidrs[1]
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "private-b"
  }
}

resource "aws_security_group" "web_sg" {
  name_prefix = "web-sg"
  vpc_id      = aws_vpc.dev_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-sg"
  }
}

resource "aws_instance" "web_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = var.key_name
  associate_public_ip_address = true

  user_data_replace_on_change = true


user_data = <<EOF
  #!/bin/bash
  yum update -y

  amazon-linux-extras install -y php8.2
  yum install -y httpd mariadb-server php-mysqlnd wget unzip

  systemctl enable httpd
  systemctl start httpd

  systemctl enable mariadb
  systemctl start mariadb

  # Wait for MariaDB to be ready
  until mysqladmin ping >/dev/null 2>&1; do
    echo "Waiting for MariaDB..."
    sleep 3
  done

  # Create DB + user
  mysql -e "CREATE DATABASE IF NOT EXISTS wordpress;"
  mysql -e "CREATE USER IF NOT EXISTS 'wpuser'@'localhost' IDENTIFIED BY 'StrongPassword123!';"
  mysql -e "ALTER USER 'wpuser'@'localhost' IDENTIFIED WITH mysql_native_password BY 'StrongPassword123!';"
  mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';"
  mysql -e "FLUSH PRIVILEGES;"

  # Install WordPress
  cd /var/www/html
  wget https://wordpress.org/latest.tar.gz
  tar -xzf latest.tar.gz
  cp -r wordpress/* .
  rm -rf wordpress latest.tar.gz

  # Configure WordPress
  cp wp-config-sample.php wp-config.php
  sed -i "s/database_name_here/wordpress/" wp-config.php
  sed -i "s/username_here/wpuser/" wp-config.php
  sed -i "s/password_here/StrongPassword123!/" wp-config.php

  # Create deck data directories
  mkdir -p /var/www/html/wp-content/decks/images

  # Download decks.json from Google Drive
  DECKS_ID="1gO_0gQeMOb5q7gjrAn6j6J21LY9GaGY1"
  wget --no-check-certificate "https://drive.google.com/uc?export=download&id=${DECKS_ID}" -O /var/www/html/wp-content/decks/decks.json

  # Download images.zip from Google Drive
  IMAGES_ID="1uoFUYy3kceQLiuvuG7dajxT_QxFSl9ul"
  wget --no-check-certificate "https://drive.google.com/uc?export=download&id=${IMAGES_ID}" -O /tmp/images.zip

  # Unzip images
  unzip /tmp/images.zip -d /var/www/html/wp-content/decks/images/
  rm -f /tmp/images.zip

  # Install plugin
  PLUGIN_DIR="/var/www/html/wp-content/plugins/decklist-generator"
  mkdir -p "${PLUGIN_DIR}"

  cat > "${PLUGIN_DIR}/decklist-generator.php" <<'EOPHP'
  <?php
  /**
   * Plugin Name: Decklist Generator
   * Description: Random One Piece TCG deck generator by leader.
   * Version: 1.0.0
   * Author: Christoph
   */

  if ( ! defined( 'ABSPATH' ) ) exit;

  define( 'DLG_PLUGIN_DIR', plugin_dir_path( __FILE__ ) );
  define( 'DLG_DECKS_JSON', WP_CONTENT_DIR . '/decks/decks.json' );
  define( 'DLG_IMAGES_DIR_URL', content_url( 'decks/images' ) );

  require_once DLG_PLUGIN_DIR . 'decklist-functions.php';

  function dlg_register_shortcodes() {
      add_shortcode( 'random_deck', 'dlg_random_deck_shortcode' );
  }
  add_action( 'init', 'dlg_register_shortcodes' );
  EOPHP

  cat > "${PLUGIN_DIR}/decklist-functions.php" <<'EOPHP'
  <?php

  if ( ! defined( 'ABSPATH' ) ) exit;

  function dlg_load_decks() {
      if ( ! file_exists( DLG_DECKS_JSON ) ) return [];
      $json = file_get_contents( DLG_DECKS_JSON );
      $data = json_decode( $json, true );
      return is_array( $data ) ? $data : [];
  }

  function dlg_filter_decks_by_leader( $decks, $leader_id ) {
      if ( empty( $leader_id ) ) return $decks;
      return array_values(array_filter($decks, fn($d) => $d['leader_id'] === $leader_id));
  }

  function dlg_pick_random_deck( $decks ) {
      return empty($decks) ? null : $decks[array_rand($decks)];
  }

  function dlg_render_deck_html( $deck ) {
      if ( ! $deck || empty($deck['cards']) ) return '<p>No deck data available.</p>';

      $leader_id = esc_html($deck['leader_id']);
      $leader_name = esc_html($deck['leader_name']);

      ob_start(); ?>
      <div class="dlg-deck">
          <h3><?php echo $leader_name; ?> (<?php echo $leader_id; ?>)</h3>
          <div class="dlg-cards">
              <?php foreach ( $deck['cards'] as $card ):
                  $id = $card['id'];
                  $name = $card['name'];
                  $count = intval($card['count']);
                  $img = trailingslashit(DLG_IMAGES_DIR_URL) . $id . '.png';
              ?>
              <div class="dlg-card">
                  <img src="<?php echo esc_url($img); ?>" style="width:100%;height:auto;">
                  <div><strong><?php echo esc_html($name); ?></strong> x<?php echo $count; ?></div>
              </div>
              <?php endforeach; ?>
          </div>
      </div>
      <style>
          .dlg-cards { display:flex; flex-wrap:wrap; gap:10px; }
          .dlg-card { width:150px; font-size:12px; }
      </style>
      <?php return ob_get_clean();
  }

  function dlg_random_deck_shortcode( $atts ) {
      $atts = shortcode_atts(['leader' => ''], $atts);
      $decks = dlg_load_decks();
      $filtered = dlg_filter_decks_by_leader($decks, $atts['leader']);
      $deck = dlg_pick_random_deck($filtered);
      return dlg_render_deck_html($deck);
  }
  EOPHP

  chown -R apache:apache /var/www/html
  chmod -R 755 /var/www/html

  systemctl restart httpd
EOF


  tags = {
    Name = "wordpress-web-server"
  }
}
