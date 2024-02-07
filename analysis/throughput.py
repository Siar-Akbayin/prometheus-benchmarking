import glob
import matplotlib.pyplot as plt
import seaborn as sns
import pandas as pd
import os


def load_and_aggregate_throughput(base_path, duration, user_configs):
    pattern = os.path.join(base_path, f"query_benchmark_results_-1reqs_{duration}secs_*users_*card_*.csv")
    files = glob.glob(pattern)

    all_data = []

    for file in files:
        df = pd.read_csv(file)
        filename = os.path.basename(file).replace('.csv', '')
        parts = filename.split('_')

        users = next((part.replace('users', '') for part in parts if 'users' in part), None)
        card = next((part.replace('card', '') for part in parts if 'card' in part), None)

        # Calculate throughput as total requests (lines in CSV minus header) divided by duration
        total_requests = len(df)
        throughput = total_requests / duration  # requests per second

        data = {
            'Users': int(users),
            'Cardinality': int(card),
            'Throughput': throughput
        }

        all_data.append(data)

    aggregated_df = pd.DataFrame(all_data)
    final_aggregated_df = aggregated_df.groupby(['Users', 'Cardinality']).agg({
        'Throughput': 'mean'
    }).reset_index()

    for users in user_configs:
        user_specific_df = final_aggregated_df[final_aggregated_df['Users'] == users]

        # Save the user-specific aggregated DataFrame to a CSV file
        filename = os.path.join("throughput", f'aggregated_throughput_data_{users}users_{duration}s.csv')
        user_specific_df.to_csv(filename, index=False)
        print(f"Aggregated throughput data for {users} users saved to {filename}")


def plot_throughput_for_users(user_configs, duration):
    for users in user_configs:
        filename = os.path.join("throughput", f'aggregated_throughput_data_{users}users_{duration}s.csv')
        if not os.path.exists(filename):
            print(f"File not found: {filename}")
            continue

        df = pd.read_csv(filename)

        plt.figure(figsize=(10, 6))
        sns.barplot(data=df, x='Cardinality', y='Throughput', palette='Greens_d')
        plt.title(f'Mean Throughput vs. Cardinality for {users} Users')
        plt.xlabel('Cardinality')
        plt.ylabel('Throughput (requests/sec)')
        plt.xticks(rotation=45)
        plt.tight_layout()

        # Save the plot
        plot_filename = os.path.join("throughput", f'mean_throughput_{users}users_{duration}s.png')
        plt.savefig(plot_filename)
        plt.close()
        print(f"Plot saved to {plot_filename}")


# Example usage
base_path = '../terraform-aws/results'
duration = 600  # Update this based on your experiment's duration
user_configs = [1, 25, 50]

load_and_aggregate_throughput(base_path, duration, user_configs)
plot_throughput_for_users(user_configs, duration)

duration = 300
load_and_aggregate_throughput(base_path, duration, user_configs)
plot_throughput_for_users(user_configs, duration)