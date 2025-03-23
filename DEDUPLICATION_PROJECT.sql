create database DeDuplication_project_2;
 use DeDuplication_project_2;
 
 create table roles (
     role_id int primary key auto_increment,
     role_name varchar(100) not null unique,
     max_Storage_quota bigint default 5368709120,
     created_at timestamp default current_timestamp
);

create table users (
      user_id bigint primary key auto_increment,
      username varchar(255) not null unique,
      email varchar(255) not null unique,
      password_hash varchar(255) not null,
      role_id int,
      storage_quota bigint default 5368709120,
      user_Storage bigint default 0,
      account_status ENUM('active','suspended','deleted'),
      created_at timestamp default current_timestamp,
      last_login timestamp,
      foreign key (role_id) references roles(role_id)
);

create table directories (
     directory_id bigint primary key auto_increment,
     parent_directory_id bigint,
     directory_name varchar(255) not null,
     directory_path varchar(1024) not null,
     owner_id bigint not null,
     created_At timestamp default current_timestamp,
     modified_at timestamp default current_timestamp,
     is_deleted boolean default false,
     foreign key (owner_id) references users(user_id),
     foreign key (parent_directory_id) references directories(directory_id) on delete cascade,
     unique index dir_path_idx (directory_path(255), owner_id)
);

create table files(
     file_id bigint primary key auto_increment,
     directory_id bigint not null,
     filename varchar(255) not null,
     file_path varchar(1024) not null,
     file_size bigint not null,
     content_hash char(64) not null,
     mime_type varchar(127),
     created_at timestamp default current_timestamp,
     modified_at timestamp default current_timestamp,
     last_accessed timestamp default current_timestamp,
     owner_id bigint not null,
     is_deleted boolean default false,
     version int default 1,
     foreign key (owner_id) references users(user_id),
     foreign key (directory_id) references directories(directory_id) on delete cascade,
     unique index file_path_idx(file_path(255), owner_id)
);

create table file_contents (
     content_hash char(64) primary key,
     content_size bigint not null,
     reference_count int default 1,
     last_referenced timestamp default current_timestamp,
     compression_type ENUM('none','gzip','iz4') default 'none',
     encrypted boolean default false,
     storage_location varchar(1024)
);


create table file_versions (
     version_id bigint primary key auto_increment,
     file_id bigint not null,
     content_hash char(64) not null,
     version_number int not null,
     created_at timestamp default current_timestamp,
     created_by bigint not null,
     file_size bigint not null,
     foreign key (file_id) references files(file_id) on delete cascade,
     foreign key (created_by) references users(user_id),
     foreign key (content_hash) references file_contents(content_hash),
     unique index file_version_idx (file_id,version_number)
);


create table shared_files (
     share_id bigint primary key auto_increment,
     file_id bigint not null,
     shared_by bigint not null,
     shared_with bigint not null,
     permission_level ENUM('read','write','admin') default 'read',
     share_expires_At timestamp null,
     created_at timestamp default current_timestamp,
     foreign key (file_id) references files(file_id) on delete cascade,
     foreign key (shared_by) references users(user_id),
     foreign key (shared_with) references users(user_id)
);

create table storage_savings (
     id bigint primary key auto_increment,
     calculation_date timestamp default current_timestamp,
     total_logical_size bigint,
     total_physical_size bigint,
     space_saved bigint,
	 deduplication_ratio decimal(10,2),
     compression_savings bigint,
     total_files int,
     duplicate_files int
);

create table file_access_logs (
     log_id bigint primary key auto_increment,
     file_id bigint not null,
     user_id bigint not null,
     access_Type ENUM('read','write','delete','share') not null,
     access_timestamp timestamp default current_timestamp,
     ip_address varchar(255),
     user_agent varchar(255),
     foreign key (file_id) references files(file_id) on delete cascade,
     foreign key (user_id) references users(user_id)
);

create index idx_content_hash on files(content_hash);

CREATE TABLE system_settings (
    setting_name VARCHAR(100) PRIMARY KEY,
    setting_value VARCHAR(100)
);


INSERT INTO system_settings (setting_name, setting_value)
VALUES ('duplicate_handling', 'rename'); 


UPDATE system_settings 
SET setting_value = 'rename' 
WHERE setting_name = 'duplicate_handling';

 
UPDATE system_settings 
SET setting_value = 'clear' 
WHERE setting_name = 'duplicate_handling';

SHOW TRIGGERS WHERE `Table` = 'files';

DELIMITER //

-- DROP TRIGGER IF EXISTS before_file_insert_handle_duplicates; 
DELIMITER //

-- DROP TRIGGER IF EXISTS before_file_insert_handle_duplicates;

CREATE TRIGGER before_file_insert_handle_duplicates
BEFORE INSERT ON files
FOR EACH ROW 
BEGIN
    DECLARE files_exists INT;
    DECLARE existing_hash CHAR(64);
    DECLARE new_filename VARCHAR(255);
    DECLARE base_name VARCHAR(255);
    DECLARE file_ext VARCHAR(255);
    DECLARE duplicate_setting VARCHAR(100);
    DECLARE unique_filename_found BOOLEAN DEFAULT FALSE;

    -- Get the duplicate handling setting
    SELECT setting_value INTO duplicate_setting
    FROM system_settings
    WHERE setting_name = 'duplicate_handling';
    
    -- Default to 'rename' if setting is not found
    IF duplicate_setting IS NULL THEN
        SET duplicate_setting = 'rename';
    END IF;
    
    -- Check for content-based duplicates (same hash)
    SELECT content_hash INTO existing_hash
    FROM files
    WHERE content_hash = NEW.content_hash
        AND directory_id = NEW.directory_id
        AND owner_id = NEW.owner_id
        AND is_deleted = false
    LIMIT 1;
    
    IF existing_hash IS NOT NULL THEN 
        IF duplicate_setting = 'rename' THEN
            
            SET base_name = SUBSTRING_INDEX(NEW.filename, '.', 1);
            IF LOCATE('.', NEW.filename) > 0 THEN
                SET file_ext = CONCAT('.', SUBSTRING_INDEX(NEW.filename, '.', -1));
            ELSE
                SET file_ext = '';
            END IF;
            
            -- Start counter at 1
            SET @counter = 1;
            
            -- Keep trying new names until we find one that doesn't exist
            WHILE unique_filename_found = FALSE DO
                IF @counter = 1 THEN
                    SET new_filename = CONCAT(base_name, '_copy', file_ext);
                ELSE
                    SET new_filename = CONCAT(base_name, '_copy', @counter, file_ext);
                END IF;
                
                -- Check if the new filename exists
                SELECT COUNT(*) INTO files_exists
                FROM files
                WHERE filename = new_filename
                    AND directory_id = NEW.directory_id
                    AND owner_id = NEW.owner_id
                    AND is_deleted = false;
                    
                IF files_exists = 0 THEN
                    -- Update filename and file_path
                    SET NEW.filename = new_filename;
                    SET NEW.file_path = CONCAT(
                        SUBSTRING_INDEX(NEW.file_path, '/', LENGTH(NEW.file_path) - LENGTH(REPLACE(NEW.file_path, '/', ''))),
                        '/',
                        new_filename
                    );
                    SET unique_filename_found = TRUE; -- Exit the loop
                ELSE
                    SET @counter = @counter + 1;
                END IF;
            END WHILE;
        ELSE
            -- If duplicate handling is not 'rename', reject the duplicate
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'Duplicate file detected. Please use a different filename.';
        END IF;
    END IF;
END //

DELIMITER ;


-- Set duplicate handling to 'rename'
UPDATE system_settings 
SET setting_value = 'rename' 
WHERE setting_name = 'duplicate_handling';

-- Insert a test role
INSERT INTO roles (role_name) 
VALUES ('test_role')
ON DUPLICATE KEY UPDATE role_id = role_id;

-- Insert a test user
INSERT INTO users (username, email, password_hash, role_id)
VALUES ('testuser1', 'test@example.com', 'hash123', 
        (SELECT role_id FROM roles WHERE role_name = 'test_role'))
ON DUPLICATE KEY UPDATE user_id = user_id;

-- Insert a test directory for the user
INSERT INTO directories (directory_name, directory_path, owner_id)
VALUES ('root', '/testuser1', 
        (SELECT user_id FROM users WHERE username = 'testuser1'))
ON DUPLICATE KEY UPDATE directory_id = directory_id;


-- first file inserted
INSERT INTO files (
    directory_id, 
    filename, 
    file_path, 
    file_size, 
    content_hash, 
    owner_id
)
SELECT 
    (SELECT directory_id FROM directories WHERE directory_name = 'root' 
     AND owner_id = (SELECT user_id FROM users WHERE username = 'testuser1')),
    'test.txt',
    '/testuser1/test.txt',
    1024,
    'hash1',
    (SELECT user_id FROM users WHERE username = 'testuser1');
    

-- second time file inserted
INSERT INTO files (
    directory_id, 
    filename, 
    file_path, 
    file_size, 
    content_hash, 
    owner_id
)
SELECT 
    (SELECT directory_id FROM directories WHERE directory_name = 'root' 
     AND owner_id = (SELECT user_id FROM users WHERE username = 'testuser1')),
    'test.txt',
    '/testuser1/test.txt',
    1024,
    'hash1',
    (SELECT user_id FROM users WHERE username = 'testuser1');
    
-- third time file inserted

INSERT INTO files (
    directory_id, 
    filename, 
    file_path, 
    file_size, 
    content_hash, 
    owner_id
)
SELECT 
    (SELECT directory_id FROM directories WHERE directory_name = 'root' 
     AND owner_id = (SELECT user_id FROM users WHERE username = 'testuser1')),
    'test.txt',
    '/testuser1/test.txt',
    1024,
    'hash1',
    (SELECT user_id FROM users WHERE username = 'testuser1');
    

SELECT filename, file_path, content_hash, is_deleted 
FROM files 
WHERE directory_id = (SELECT directory_id 
                       FROM directories 
                       WHERE directory_name = 'root' 
                       AND owner_id = (SELECT user_id 
                                       FROM users 
                                       WHERE username = 'testuser1'))
ORDER BY created_at;



SET SQL_SAFE_UPDATES = 0;


CREATE TEMPORARY TABLE temp_unique_files AS
SELECT MIN(file_id) AS file_id
FROM files
GROUP BY content_hash, directory_id;

-- Delete duplicate files 
DELETE FROM files
WHERE file_id NOT IN (SELECT file_id FROM temp_unique_files);







-- another operation of linking duplicates
DROP TRIGGER IF EXISTS before_file_insert_link_duplicates;

DELIMITER //

CREATE TRIGGER after_file_insert_link_duplicates
AFTER INSERT ON files
FOR EACH ROW
BEGIN
    DECLARE existing_file_id BIGINT;

    -- content-based duplicates (same hash)
    SELECT file_id INTO existing_file_id
    FROM files
    WHERE content_hash = NEW.content_hash
        AND is_deleted = false
    LIMIT 1;

    IF existing_file_id IS NOT NULL AND existing_file_id != NEW.file_id THEN
        -- Link this file
        INSERT INTO file_duplicates (file_id, duplicate_file_id)
        VALUES (NEW.file_id, existing_file_id);
    END IF;
END //

DELIMITER ;


CREATE TABLE file_duplicates (
    file_id BIGINT NOT NULL,
    duplicate_file_id BIGINT NOT NULL,
    PRIMARY KEY (file_id, duplicate_file_id),
    FOREIGN KEY (file_id) REFERENCES files(file_id) ON DELETE CASCADE,
    FOREIGN KEY (duplicate_file_id) REFERENCES files(file_id) ON DELETE CASCADE
);

INSERT INTO files (directory_id, filename, file_path, file_size, content_hash, owner_id)
VALUES 
    (1, 'file1.txt', '/root/file1.txt', 1024, 'hash1', 1),
    (1, 'file2.txt', '/root/file2.txt', 2048, 'hash2', 1);

INSERT INTO files (directory_id, filename, file_path, file_size, content_hash, owner_id)
VALUES 
    (1, 'duplicate_file1.txt', '/root/duplicate_file1.txt', 1024, 'hash1', 1);

SELECT * FROM file_duplicates;

SELECT fd.file_id AS OriginalFileID, 
       f1.filename AS OriginalFileName, 
       fd.duplicate_file_id AS DuplicateFileID, 
       f2.filename AS DuplicateFileName
FROM file_duplicates fd
JOIN files f1 ON fd.file_id = f1.file_id
JOIN files f2 ON fd.duplicate_file_id = f2.file_id;

SELECT file_id, filename, content_hash FROM files WHERE content_hash = 'hash1';





-- finding duplicates using metadata


SELECT * FROM files WHERE is_deleted = FALSE AND (content_hash IS NOT NULL AND filename IS NOT NULL);
