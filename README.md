# SQL File Management and Deduplication Project

# 📌 Project Overview

## This project implements a file management system with built-in data deduplication using SQL. It provides a structured way to store files, prevent duplicates, and optimize storage by linking duplicate files rather than storing them multiple times.

## 📂 Repository Structure
  - [DEDUPLICATION_PROJECT.sql](DEDUPLICATION_PROJECT.sql)   #SQL file Database, Handling Duplication, & Testing 
  - [README.md](readme.md)                                   # Project documentation

## 🛠️ Requirements
  - Database System: MySQL
  - SQL Client: MySQL Workbench / Any SQL CLI
  - Storage Management: Deduplication logic using SQL triggers

## 🚀 Setup Instructions
 - 1️⃣ Install MySQL (Skip if already installed)Download from MySQL Official Site and install it.
 - 2️⃣ Create a new database
 - 3️⃣ Run the schema script to create tables
 - 4️⃣ Load sample data
 - 5️⃣ Enable the deduplication trigger


# 🔄 Deduplication Logic
 ## This project ensures that files with the same content are not stored multiple times. Instead, it:
  - Checks for existing files based on content hash
  - Handles duplicate file names by renaming or rejecting duplicates
  - Uses a file_contents table to store unique file data
  - Links duplicate files using file_duplicates table

# 📊 Expected Behavior
  - When a duplicate file is uploaded, the system either renames it (file_copy, file_copy1, etc.) or rejects it based on settings.
  - Files with the same content but different names are linked in file_duplicates.
  - Space-saving calculations are tracked in the storage_savings table.

# 📝 Sample Query Output
  Example of checking duplicate files:
   `SELECT filename, file_path, content_hash, is_deleted 
    FROM files 
    WHERE directory_id = (SELECT directory_id 
                       FROM directories 
                       WHERE directory_name = 'root' 
                       AND owner_id = (SELECT user_id 
                                       FROM users 
                                       WHERE username = 'testuser1'))
   ORDER BY created_at;`

# 🏆 Contributing
  Contributions are welcome! If you find any improvements or optimizations, open a pull request. 🚀

# 📩 Contact
  For any questions, reach out via GitHub Issues or email at your_email@example.com.

📌 Ensure all queries and triggers are tested before submission to avoid errors!
