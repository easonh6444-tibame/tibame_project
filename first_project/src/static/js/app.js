// Nebula Dash - Control Center Interactive Engine

document.addEventListener('DOMContentLoaded', () => {
    // DOM Elements
    const serverStatus = document.getElementById('server-status');
    const serverUptime = document.getElementById('server-uptime');
    const cpuVal = document.getElementById('cpu-val');
    const cpuProgress = document.getElementById('cpu-progress');
    const memVal = document.getElementById('mem-val');
    const memProgress = document.getElementById('mem-progress');
    const networkVal = document.getElementById('network-val');
    const sessionsVal = document.getElementById('sessions-val');
    const dbVal = document.getElementById('db-val');
    
    const taskForm = document.getElementById('task-form');
    const taskTitleInput = document.getElementById('task-title-input');
    const taskDescInput = document.getElementById('task-desc-input');
    const taskListElement = document.getElementById('task-list-element');
    const tasksLoader = document.getElementById('tasks-loader');

    // SVG Circle Radius math
    const CIRCUMFERENCE = 314.16; // 2 * pi * r = 2 * 3.14159 * 50

    // Set Status Dot color
    const setStatusOnline = (isOnline) => {
        const dot = document.querySelector('.status-dot');
        if (isOnline) {
            dot.className = 'status-dot online';
            serverStatus.textContent = 'Online';
            serverStatus.className = 'value accent-green';
        } else {
            dot.className = 'status-dot pulsing';
            serverStatus.textContent = 'Offline';
            serverStatus.className = 'value accent-pink';
        }
    };

    // Format Uptime (seconds to structured string)
    const formatUptime = (seconds) => {
        if (seconds < 60) return `${seconds}s`;
        const mins = Math.floor(seconds / 60);
        const secs = seconds % 60;
        if (mins < 60) return `${mins}m ${secs}s`;
        const hrs = Math.floor(mins / 60);
        const remainingMins = mins % 60;
        return `${hrs}h ${remainingMins}m`;
    };

    // Update Progress Circular SVG
    const updateProgressRing = (element, pct) => {
        const offset = CIRCUMFERENCE - (pct / 100) * CIRCUMFERENCE;
        element.style.strokeDashoffset = offset;
    };

    // Sync Server Stats
    const fetchServerStats = async () => {
        try {
            const response = await fetch('/api/status');
            if (!response.ok) throw new Error('Network error');
            const data = await response.json();
            
            setStatusOnline(true);
            
            // Update CPU UI
            const cpu = data.metrics.cpu_usage_pct;
            cpuVal.textContent = `${cpu}%`;
            updateProgressRing(cpuProgress, cpu);

            // Update Memory UI
            const mem = data.metrics.memory_usage_pct;
            memVal.textContent = `${mem}%`;
            updateProgressRing(memProgress, mem);

            // Other Metrics
            networkVal.textContent = `${data.metrics.network_throughput_mbps} MB/s`;
            sessionsVal.textContent = data.metrics.active_sessions;
            dbVal.textContent = data.metrics.database_connection.toUpperCase();
            serverUptime.textContent = formatUptime(data.uptime);
            
        } catch (error) {
            console.error('Failed to sync metrics:', error);
            setStatusOnline(false);
        }
    };

    // Task Templates & Rendering
    const createTaskItemDOM = (task) => {
        const li = document.createElement('li');
        li.className = `task-item ${task.completed ? 'completed' : ''}`;
        li.id = `task-item-${task.id}`;

        li.innerHTML = `
            <div class="task-info-group">
                <label class="checkbox-container">
                    <input type="checkbox" class="task-checkbox" data-id="${task.id}" ${task.completed ? 'checked' : ''}>
                    <span class="checkmark"></span>
                </label>
                <div class="task-texts">
                    <div class="task-title">${escapeHTML(task.title)}</div>
                    ${task.description ? `<div class="task-desc">${escapeHTML(task.description)}</div>` : ''}
                </div>
            </div>
            <button class="btn-delete" data-id="${task.id}" title="Delete Task">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polyline points="3 6 5 6 21 6"></polyline>
                    <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
                    <line x1="10" y1="11" x2="10" y2="17"></line>
                    <line x1="14" y1="11" x2="14" y2="17"></line>
                </svg>
            </button>
        `;

        // Bind Checkbox Toggle
        const checkbox = li.querySelector('.task-checkbox');
        checkbox.addEventListener('change', async (e) => {
            const taskId = e.target.getAttribute('data-id');
            const completed = e.target.checked;
            try {
                const response = await fetch(`/api/tasks/${taskId}`, {
                    method: 'PATCH',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ completed })
                });
                if (!response.ok) throw new Error('Update failed');
                
                if (completed) {
                    li.classList.add('completed');
                } else {
                    li.classList.remove('completed');
                }
            } catch (err) {
                console.error(err);
                e.target.checked = !completed; // Revert checkbox UI state
            }
        });

        // Bind Delete Event
        const deleteBtn = li.querySelector('.btn-delete');
        deleteBtn.addEventListener('click', async () => {
            const taskId = deleteBtn.getAttribute('data-id');
            if (confirm('Are you sure you want to delete this task?')) {
                try {
                    const response = await fetch(`/api/tasks/${taskId}`, {
                        method: 'DELETE'
                    });
                    if (!response.ok) throw new Error('Deletion failed');
                    
                    // Smooth exit animation
                    li.style.opacity = '0';
                    li.style.transform = 'translateX(20px)';
                    setTimeout(() => {
                        li.remove();
                    }, 300);
                } catch (err) {
                    console.error(err);
                }
            }
        });

        return li;
    };

    // Escape HTML Helper to prevent XSS
    const escapeHTML = (str) => {
        return str.replace(/[&<>'"]/g, 
            tag => ({
                '&': '&amp;',
                '<': '&lt;',
                '>': '&gt;',
                "'": '&#39;',
                '"': '&quot;'
            }[tag] || tag)
        );
    };

    // Load Tasks from API
    const loadTasks = async () => {
        try {
            const response = await fetch('/api/tasks');
            if (!response.ok) throw new Error('Failed to load tasks');
            const tasksList = await response.json();
            
            taskListElement.innerHTML = '';
            tasksLoader.style.display = 'none';

            if (tasksList.length === 0) {
                taskListElement.innerHTML = '<li class="task-item" style="justify-content: center; color: var(--text-muted);">No active tasks found.</li>';
                return;
            }

            tasksList.forEach(task => {
                const taskDOM = createTaskItemDOM(task);
                taskListElement.appendChild(taskDOM);
            });

        } catch (error) {
            console.error('Error fetching tasks:', error);
            tasksLoader.innerHTML = '<span>⚠️ Sync Failed</span>';
        }
    };

    // Form submission to create a task
    taskForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const title = taskTitleInput.value.trim();
        const description = taskDescInput.value.trim();

        if (!title) return;

        try {
            const response = await fetch('/api/tasks', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ title, description })
            });

            if (!response.ok) throw new Error('Failed to create task');
            const newTask = await response.json();

            // Clear inputs
            taskTitleInput.value = '';
            taskDescInput.value = '';

            // If empty message is showing, remove it
            if (taskListElement.children.length === 1 && taskListElement.firstChild.style.justifyContent === 'center') {
                taskListElement.innerHTML = '';
            }

            // Insert new task at the top (since the list matches creation time descending)
            const taskDOM = createTaskItemDOM(newTask);
            taskListElement.insertBefore(taskDOM, taskListElement.firstChild);

        } catch (err) {
            console.error('Error creating task:', err);
            alert('Failed to save task. Please try again.');
        }
    });

    // Start Loops & Synchronization
    fetchServerStats();
    loadTasks();
    setInterval(fetchServerStats, 3000); // refresh system info every 3 seconds
});
