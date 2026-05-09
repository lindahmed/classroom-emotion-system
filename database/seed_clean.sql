-- =============================================================================
-- EduPulse AI — Seed Data (cleaned)
-- Initial data for departments, rooms, semester, courses, demo users, settings
-- =============================================================================

-- Departments
INSERT INTO departments (department_name, department_code, building) VALUES
    ('Computer Science', 'CS', 'Science Building'),
    ('Mathematics', 'MATH', 'Science Building')
ON CONFLICT (department_code) DO NOTHING;

-- Rooms (from current CSV data: Room 204, Room 305, Room 401, Room 501)
INSERT INTO rooms (room_number, building, capacity, room_type, equipment) VALUES
    ('Room 204', 'Science Building', 30, 'Lecture Hall', ARRAY['projector', 'camera', 'whiteboard']),
    ('Room 305', 'Science Building', 30, 'Lecture Hall', ARRAY['projector', 'camera', 'whiteboard']),
    ('Room 401', 'Science Building', 30, 'Lecture Hall', ARRAY['projector', 'camera', 'whiteboard']),
    ('Room 501', 'Science Building', 30, 'Lecture Hall', ARRAY['projector', 'camera', 'whiteboard'])
ON CONFLICT (room_number, building) DO NOTHING;

-- Semesters
INSERT INTO semesters (semester_id, semester_name, start_date, end_date, is_active) VALUES
    ('SPRING2026', 'Spring 2026', '2026-02-09', '2026-05-31', TRUE)
ON CONFLICT (semester_id) DO NOTHING;

-- Courses
INSERT INTO courses (course_code, course_name, department_id, credit_hours, description) VALUES
    ('CS301', 'Artificial Intelligence',
        (SELECT department_id FROM departments WHERE department_code = 'CS'), 3,
        'Fundamentals of AI including search, reasoning, and machine learning'),
    ('CS302', 'Data Science Fundamentals',
        (SELECT department_id FROM departments WHERE department_code = 'CS'), 3,
        'Introduction to data science, statistical analysis, and data visualization'),
    ('CS401', 'Advanced Machine Learning',
        (SELECT department_id FROM departments WHERE department_code = 'CS'), 4,
        'Advanced topics in ML including deep learning, NLP, and reinforcement learning'),
    ('MATH201', 'Statistics for Data Analysis',
        (SELECT department_id FROM departments WHERE department_code = 'MATH'), 3,
        'Statistical methods for data analysis and interpretation')
ON CONFLICT (course_code) DO NOTHING;

-- Semester Weeks (16 weeks: Feb 9 - May 24, 2026)
INSERT INTO semester_weeks (semester_id, academic_week, week_label, start_date, end_date, status) VALUES
    ('SPRING2026', 1,  'Week 1',  '2026-02-09', '2026-02-15', 'completed'),
    ('SPRING2026', 2,  'Week 2',  '2026-02-16', '2026-02-22', 'completed'),
    ('SPRING2026', 3,  'Week 3',  '2026-02-23', '2026-03-01', 'completed'),
    ('SPRING2026', 4,  'Week 4',  '2026-03-02', '2026-03-08', 'completed'),
    ('SPRING2026', 5,  'Week 5',  '2026-03-09', '2026-03-15', 'completed'),
    ('SPRING2026', 6,  'Week 6',  '2026-03-16', '2026-03-22', 'completed'),
    ('SPRING2026', 7,  'Week 7',  '2026-03-23', '2026-03-29', 'completed'),
    ('SPRING2026', 8,  'Week 8',  '2026-03-30', '2026-04-05', 'completed'),
    ('SPRING2026', 9,  'Week 9',  '2026-04-06', '2026-04-12', 'completed'),
    ('SPRING2026', 10, 'Week 10', '2026-04-13', '2026-04-19', 'completed'),
    ('SPRING2026', 11, 'Week 11', '2026-04-20', '2026-04-26', 'completed'),
    ('SPRING2026', 12, 'Week 12', '2026-04-27', '2026-05-03', 'completed'),
    ('SPRING2026', 13, 'Week 13', '2026-05-04', '2026-05-10', 'active'),
    ('SPRING2026', 14, 'Week 14', '2026-05-11', '2026-05-17', 'scheduled'),
    ('SPRING2026', 15, 'Week 15', '2026-05-18', '2026-05-24', 'scheduled'),
    ('SPRING2026', 16, 'Week 16', '2026-05-25', '2026-05-31', 'scheduled')
ON CONFLICT (semester_id, academic_week) DO NOTHING;

-- Test User Accounts (password: EduPulse#2026)
INSERT INTO users (username, email, password_hash, role, institution_id, is_active) VALUES
    ('lindahmed05', 'lindahmed05@gmail.com', '$2b$12$CWKRn/VoDczoTxwwiya5U.U9jITzkAYfY36E/mZjBIW0WrIe9XBzy', 'student', 'S001', TRUE),
    ('minayoussef', 'Minayoussef027@gmail.com', '$2b$12$CWKRn/VoDczoTxwwiya5U.U9jITzkAYfY36E/mZjBIW0WrIe9XBzy', 'admin', 'A001', TRUE),
    ('linda2ahmed', 'linda2ahmed02@gmail.com', '$2b$12$CWKRn/VoDczoTxwwiya5U.U9jITzkAYfY36E/mZjBIW0WrIe9XBzy', 'lecturer', 'L001', TRUE),
    ('rawanelsawaby', 'rawanelsawaby@gmail.com', '$2b$12$CWKRn/VoDczoTxwwiya5U.U9jITzkAYfY36E/mZjBIW0WrIe9XBzy', 'student', 'S002', TRUE)
ON CONFLICT (email) DO NOTHING;

-- Student Profiles
INSERT INTO students (user_id, student_code, full_name, enrollment_year) VALUES
    ((SELECT user_id FROM users WHERE email = 'lindahmed05@gmail.com'), 'S001', 'Linda Ahmed', EXTRACT(YEAR FROM NOW())::integer),
    ((SELECT user_id FROM users WHERE email = 'rawanelsawaby@gmail.com'), 'S002', 'Rawan Elsawaby', EXTRACT(YEAR FROM NOW())::integer)
ON CONFLICT (user_id) DO NOTHING;

-- Lecturer Profile
INSERT INTO lecturers (user_id, lecturer_code, full_name) VALUES
    ((SELECT user_id FROM users WHERE email = 'linda2ahmed02@gmail.com'), 'L001', 'Dr. Linda Ahmed')
ON CONFLICT (user_id) DO NOTHING;

-- Admin Profile
INSERT INTO admins (user_id, full_name) VALUES
    ((SELECT user_id FROM users WHERE email = 'Minayoussef027@gmail.com'), 'Mina Youssef')
ON CONFLICT (user_id) DO NOTHING;

-- Student Groups
INSERT INTO student_groups (group_name, group_code, course_id, semester_id) VALUES
    ('Group A - CS301', 'GRP_A_CS301', (SELECT course_id FROM courses WHERE course_code = 'CS301'), 'SPRING2026'),
    ('Group B - CS301', 'GRP_B_CS301', (SELECT course_id FROM courses WHERE course_code = 'CS301'), 'SPRING2026'),
    ('Group A - CS302', 'GRP_A_CS302', (SELECT course_id FROM courses WHERE course_code = 'CS302'), 'SPRING2026')
ON CONFLICT (group_code, semester_id) DO NOTHING;

-- Group Memberships
INSERT INTO group_memberships (group_id, student_id) VALUES
    ((SELECT group_id FROM student_groups WHERE group_code = 'GRP_A_CS301'), 
     (SELECT student_id FROM students WHERE student_code = 'S001')),
    ((SELECT group_id FROM student_groups WHERE group_code = 'GRP_B_CS301'), 
     (SELECT student_id FROM students WHERE student_code = 'S002')),
    ((SELECT group_id FROM student_groups WHERE group_code = 'GRP_A_CS302'), 
     (SELECT student_id FROM students WHERE student_code = 'S001'))
ON CONFLICT (group_id, student_id) DO NOTHING;

-- Lecturer Course Assignments
INSERT INTO lecturer_course_assignments (lecturer_id, course_id, group_id, semester_id, role) VALUES
    ((SELECT lecturer_id FROM lecturers WHERE user_id = (SELECT user_id FROM users WHERE email = 'linda2ahmed02@gmail.com')),
     (SELECT course_id FROM courses WHERE course_code = 'CS301'),
     (SELECT group_id FROM student_groups WHERE group_code = 'GRP_A_CS301'),
     'SPRING2026', 'primary'),
    ((SELECT lecturer_id FROM lecturers WHERE user_id = (SELECT user_id FROM users WHERE email = 'linda2ahmed02@gmail.com')),
     (SELECT course_id FROM courses WHERE course_code = 'CS301'),
     (SELECT group_id FROM student_groups WHERE group_code = 'GRP_B_CS301'),
     'SPRING2026', 'primary'),
    ((SELECT lecturer_id FROM lecturers WHERE user_id = (SELECT user_id FROM users WHERE email = 'linda2ahmed02@gmail.com')),
     (SELECT course_id FROM courses WHERE course_code = 'CS302'),
     (SELECT group_id FROM student_groups WHERE group_code = 'GRP_A_CS302'),
     'SPRING2026', 'primary')
ON CONFLICT (lecturer_id, course_id, group_id, semester_id) DO NOTHING;

-- System Settings
INSERT INTO system_settings (setting_key, setting_value, setting_type, description) VALUES
    ('confusion_threshold', '0.30', 'float', 'Threshold for confusion spike alerts (percentage of confused students)'),
    ('boredom_threshold', '0.30', 'float', 'Threshold for boredom spike alerts'),
    ('capture_interval_seconds', '5', 'integer', 'Seconds between camera frame captures'),
    ('model_name', 'EduPulse_v1.0', 'string', 'Default emotion detection model name'),
    ('session_timeout_hours', '24', 'integer', 'Login session expiration in hours'),
    ('max_login_attempts', '5', 'integer', 'Max failed login attempts before lockout'),
    ('app_version', '0.3.0', 'string', 'Current application version'),
    ('institution_name', 'University', 'string', 'Institution display name')
ON CONFLICT (setting_key) DO NOTHING;
