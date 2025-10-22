# scripts/fetch_data.py
"""
NYC Real Estate Data Fetching via Socrata API
Automatically downloads NYC property sales data using the official API
"""

import pandas as pd
import requests
from datetime import datetime, timedelta
from pathlib import Path
import logging
import time

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class NYCDataFetcher:
    def __init__(self):
        # NYC Open Data API endpoints
        self.base_url = "https://data.cityofnewyork.us/resource"
        self.sales_endpoint = "usep-8jbt.json"  # NYC Citywide Rolling Calendar Sales
        
        # Directory setup
        self.data_dir = Path("data/raw")
        self.data_dir.mkdir(parents=True, exist_ok=True)
        
        # API parameters
        self.limit = 50000  # Records per request (API maximum)
        self.timeout = 30  # Request timeout in seconds
    
    def fetch_sales_data(self, start_date="2019-01-01", end_date=None, app_token=None):
        """
        Fetch NYC property sales data from Socrata API
        
        Args:
            start_date: Start date for data (YYYY-MM-DD format)
            end_date: End date for data (defaults to today)
            app_token: Optional Socrata app token for higher rate limits
        
        Returns:
            DataFrame with sales data
        """
        if end_date is None:
            end_date = datetime.now().strftime("%Y-%m-%d")
        
        logger.info(f"Fetching NYC property sales data from {start_date} to {end_date}")
        logger.info("Using Socrata Open Data API")
        
        all_data = []
        offset = 0
        total_fetched = 0
        
        # Build headers
        headers = {}
        if app_token:
            headers['X-App-Token'] = app_token
            logger.info("Using app token for higher rate limits")
        
        while True:
            try:
                # Build API query with SoQL (Socrata Query Language)
                params = {
                    "$limit": self.limit,
                    "$offset": offset,
                    "$where": f"sale_date >= '{start_date}' AND sale_date <= '{end_date}'",
                    "$order": "sale_date DESC"
                }
                
                # Make API request
                url = f"{self.base_url}/{self.sales_endpoint}"
                logger.info(f"Requesting records {offset} to {offset + self.limit}...")
                
                response = requests.get(url, params=params, headers=headers, timeout=self.timeout)
                response.raise_for_status()
                
                # Parse JSON response
                data = response.json()
                
                if not data:
                    logger.info("No more records to fetch")
                    break
                
                all_data.extend(data)
                total_fetched += len(data)
                logger.info(f"Fetched {len(data)} records (Total: {total_fetched:,})")
                
                # Check if we got fewer records than limit (last page)
                if len(data) < self.limit:
                    logger.info("Reached end of dataset")
                    break
                
                offset += self.limit
                
                # Be nice to the API - small delay between requests
                time.sleep(0.5)
                
            except requests.exceptions.RequestException as e:
                logger.error(f"API request failed: {str(e)}")
                if offset > 0:
                    logger.info(f"Returning {total_fetched:,} records fetched so far")
                    break
                else:
                    raise
        
        # Convert to DataFrame
        df = pd.DataFrame(all_data)
        logger.info(f"Successfully fetched {len(df):,} total records")
        
        # Save raw data
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"nyc_property_sales_{start_date}_{end_date}_{timestamp}.csv"
        filepath = self.data_dir / filename
        
        df.to_csv(filepath, index=False)
        logger.info(f"Raw data saved to: {filepath}")
        
        # Also save as the standard filename for the pipeline
        standard_path = self.data_dir / "nyc_property_sales.csv"
        df.to_csv(standard_path, index=False)
        logger.info(f"Data also saved as: {standard_path}")
        
        return df
    
    def get_dataset_info(self):
        """Get metadata about the dataset"""
        try:
            # Fetch dataset metadata
            metadata_url = "https://data.cityofnewyork.us/api/views/usep-8jbt.json"
            response = requests.get(metadata_url, timeout=self.timeout)
            response.raise_for_status()
            
            metadata = response.json()
            
            logger.info("Dataset Information:")
            logger.info(f"Name: {metadata.get('name', 'N/A')}")
            logger.info(f"Description: {metadata.get('description', 'N/A')[:200]}...")
            logger.info(f"Rows: {metadata.get('rowsUpdatedAt', 'N/A')}")
            logger.info(f"Last Updated: {metadata.get('rowsUpdatedAt', 'N/A')}")
            
            # Get column information
            if 'columns' in metadata:
                logger.info(f"Total Columns: {len(metadata['columns'])}")
                logger.info("\nKey Columns:")
                for col in metadata['columns'][:10]:  # Show first 10 columns
                    logger.info(f"  - {col.get('name', 'N/A')}: {col.get('dataTypeName', 'N/A')}")
            
            return metadata
            
        except Exception as e:
            logger.error(f"Failed to fetch dataset metadata: {str(e)}")
            return None
    
    def fetch_recent_data(self, days=365):
        """Fetch data from the last N days"""
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days)
        
        return self.fetch_sales_data(
            start_date=start_date.strftime("%Y-%m-%d"),
            end_date=end_date.strftime("%Y-%m-%d")
        )


def main():
    """Main execution function"""
    print("=" * 60)
    print("NYC Real Estate Data Fetcher")
    print("=" * 60)
    print()
    
    fetcher = NYCDataFetcher()
    
    # Optional: Get dataset information
    print("Fetching dataset information...")
    fetcher.get_dataset_info()
    print()
    
    # Choose your data range
    print("Choose data fetching option:")
    print("1. Last 12 months (fastest, good for testing)")
    print("2. Last 24 months (recommended for analysis)")
    print("3. Since 2019 (comprehensive, may take 5-10 minutes)")
    print("4. Custom date range")
    
    choice = input("\nEnter choice (1-4) [default: 2]: ").strip() or "2"
    
    try:
        if choice == "1":
            logger.info("Fetching last 12 months of data...")
            df = fetcher.fetch_recent_data(days=365)
        
        elif choice == "2":
            logger.info("Fetching last 24 months of data...")
            df = fetcher.fetch_recent_data(days=730)
        
        elif choice == "3":
            logger.info("Fetching data since 2019...")
            df = fetcher.fetch_sales_data(start_date="2019-01-01")
        
        elif choice == "4":
            start = input("Enter start date (YYYY-MM-DD): ").strip()
            end = input("Enter end date (YYYY-MM-DD) [default: today]: ").strip()
            df = fetcher.fetch_sales_data(start_date=start, end_date=end if end else None)
        
        else:
            logger.warning("Invalid choice, using default (last 24 months)")
            df = fetcher.fetch_recent_data(days=730)
        
        # Display summary
        print("\n" + "=" * 60)
        print("DATA FETCH SUMMARY")
        print("=" * 60)
        print(f"Total Records: {len(df):,}")
        print(f"Columns: {len(df.columns)}")
        print(f"\nColumn Names:\n{', '.join(df.columns.tolist())}")
        print(f"\nDate Range: {df['sale_date'].min()} to {df['sale_date'].max()}")
        print(f"\nSample Data:")
        print(df.head())
        print("\n✅ Data fetch completed successfully!")
        print("📁 Next step: Run 'python scripts/clean_data.py' to clean the data")
        
    except Exception as e:
        logger.error(f"Failed to fetch data: {str(e)}")
        print("\n⚠️ If you're hitting rate limits, consider:")
        print("1. Register for a free Socrata app token: https://dev.socrata.com/")
        print("2. Use a smaller date range")
        print("3. Add delays between requests (already implemented)")


if __name__ == "__main__":
    main()