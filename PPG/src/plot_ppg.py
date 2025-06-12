import serial
import matplotlib.pyplot as plt
from collections import deque
import sys
import numpy as np

# Configure the serial port
serial_port = '/dev/tty.usbserial-0001'  # Your ESP32 port
baud_rate = 115200

try:
    ser = serial.Serial(serial_port, baud_rate, timeout=3)
    print(f"Successfully connected to {serial_port}")
except serial.SerialException as e:
    print(f"Error connecting to {serial_port}: {e}")
    sys.exit(1)

# Buffer size for plotting
buffer_size = 200
red_data = deque([0] * buffer_size, maxlen=buffer_size)
ir_data = deque([0] * buffer_size, maxlen=buffer_size)

# Set up the plot with two subplots
plt.ion()
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 8))

# Plot lines for both LEDs
line_red, = ax1.plot(red_data, label="Red LED", color="red")
line_ir, = ax2.plot(ir_data, label="IR LED", color="blue")

# Configure plots
ax1.set_title("Red LED PPG Signal")
ax1.set_ylabel("Sensor Values")
ax1.legend()

ax2.set_title("IR LED PPG Signal")
ax2.set_xlabel("Time")
ax2.set_ylabel("Sensor Values")
ax2.legend()

# Apply tight layout
plt.tight_layout()
print("Plot initialized and waiting for data...")

# Simple moving average filter
def moving_average(data, window_size=5):
    if len(data) < window_size:
        return list(data)
    return list(np.convolve(data, np.ones(window_size)/window_size, mode='valid'))

try:
    while True:
        if ser.in_waiting > 0:
            line = ser.readline().decode('utf-8', errors='replace').strip()
            print(f"Received: {line}")
            
            # Parse both Red LED and IR LED values
            if "Red LED:" in line and ", IR LED:" in line:
                try:
                    # Extract Red LED value
                    red_part = line.split(", IR LED:")[0]
                    red_value = int(red_part.split("Red LED:")[1].strip())
                    
                    # Extract IR LED value
                    ir_value = int(line.split(", IR LED:")[1].strip())
                    
                    print(f"Parsed - Red: {red_value}, IR: {ir_value}")
                    
                    # Add values to buffers
                    red_data.append(red_value)
                    ir_data.append(ir_value)
                    
                    # Apply smoothing for better visualization
                    smoothed_red = moving_average(red_data)
                    smoothed_ir = moving_average(ir_data)
                    
                    # Update Red LED plot
                    if len(red_data) > 5:  # Wait until we have enough data
                        data_min = min(smoothed_red)
                        data_max = max(smoothed_red) 
                        margin = (data_max - data_min) * 0.1 or 100  # 10% margin or at least 100
                        ax1.set_ylim(data_min - margin, data_max + margin)
                    
                    line_red.set_ydata(smoothed_red)
                    line_red.set_xdata(range(len(smoothed_red)))
                    
                    # Update IR LED plot
                    if len(ir_data) > 5:  # Wait until we have enough data
                        data_min = min(smoothed_ir)
                        data_max = max(smoothed_ir)
                        margin = (data_max - data_min) * 0.1 or 100  # 10% margin or at least 100
                        ax2.set_ylim(data_min - margin, data_max + margin)
                    
                    line_ir.set_ydata(smoothed_ir)
                    line_ir.set_xdata(range(len(smoothed_ir)))
                    
                    # Refresh plots
                    ax1.relim()
                    ax1.autoscale_view(scalex=True, scaley=False)
                    ax2.relim()
                    ax2.autoscale_view(scalex=True, scaley=False)
                    plt.draw()
                    plt.pause(0.01)
                
                except ValueError as e:
                    print(f"Error parsing values: {e}")
                except IndexError as e:
                    print(f"Error extracting values: {e}")
        
        else:
            plt.pause(0.1)  # Small pause to prevent CPU hogging

except KeyboardInterrupt:
    print("\nExiting...")
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()
finally:
    ser.close()
    plt.close()