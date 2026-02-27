# AWS-Capstone-Project

This Project implements an EC2 Wordpress instance in AWS, with two Main functionalities:

1. Output a random deck-list of the One Piece TCG dependent on a leader the user of the website chooses
2. Output a Ai Generated Deck-List based on a Leader chosen

The .tf files are used in Terraform to create the architecture of the project. The deck-lists and the card images are taken via the API of "dotgg.gg". These will be stored in an s3-bucket and the deck-lists are also used to train AI-models locally and then also stored in the s3-bucket.

The user-data.sh installs the database, gets the data and includes a php script which adds the funcionality of the wordpress instance. 

<img width="1866" height="905" alt="Untitled-2026-01-09-1031" src="https://github.com/user-attachments/assets/6cbc1d33-5b0b-4092-8e83-7fc6ed53856d" />
