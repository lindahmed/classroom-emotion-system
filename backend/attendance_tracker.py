import time

class AttendanceTracker:
    def __init__(self):
        self.sessions = {}  # lecture_id -> {student_id: {'last_seen': timestamp, 'status': 'Present/Absent/Left/Returned', 'absence_duration': 0}}

    def update_attendance(self, lecture_id, student_id):
        if lecture_id not in self.sessions:
            self.sessions[lecture_id] = {}
        session = self.sessions[lecture_id]
        current_time = time.time()
        if student_id not in session:
            session[student_id] = {'last_seen': current_time, 'status': 'Present', 'absence_duration': 0}
        else:
            last_seen = session[student_id]['last_seen']
            if current_time - last_seen > 30:  # 30 seconds
                if session[student_id]['status'] == 'Present':
                    session[student_id]['status'] = 'Left'
                    session[student_id]['absence_duration'] = current_time - last_seen
                elif session[student_id]['status'] == 'Left':
                    session[student_id]['status'] = 'Returned'
                    # absence_duration remains
            else:
                session[student_id]['status'] = 'Present'
            session[student_id]['last_seen'] = current_time

    def get_attendance_status(self, lecture_id, student_id):
        if lecture_id in self.sessions and student_id in self.sessions[lecture_id]:
            return self.sessions[lecture_id][student_id]['status']
        return 'Absent'

    def get_session_status(self, lecture_id):
        return self.sessions.get(lecture_id, {})

tracker = AttendanceTracker()
