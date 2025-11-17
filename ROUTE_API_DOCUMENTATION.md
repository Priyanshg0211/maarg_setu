# Route API Documentation

## Which API to Use for Live Routes

### **Google Maps Directions API** ✅ (Currently Used)

**API Endpoint:**
```
https://maps.googleapis.com/maps/api/directions/json
```

**Why This API:**
1. **Real-time Traffic Data**: Provides routes with current traffic conditions
2. **Multiple Route Options**: Supports alternative routes
3. **Detailed Route Information**: Includes turn-by-turn directions, distance, duration, and polyline data
4. **Live Updates**: Can be called repeatedly with updated origin (current location) to get fresh routes

**Key Features:**
- ✅ Real-time traffic-aware routing
- ✅ Multiple route alternatives
- ✅ Turn-by-turn navigation steps
- ✅ Distance and duration calculations
- ✅ Encoded polyline for route visualization
- ✅ Supports different travel modes (driving, walking, transit, etc.)

**How It Works for Live Routes:**
1. **Initial Route Fetch**: When drop location is set, fetch route from current location to destination
2. **Real-time Updates**: During navigation, periodically call the API with updated current location as origin
3. **Rerouting**: Automatically reroute if user deviates more than 50 meters from the route
4. **Traffic Updates**: Fetch fresh routes every 30 seconds to get latest traffic conditions

**API Parameters:**
```
origin: Current location (lat,lng)
destination: Drop location (lat,lng)
key: Your Google Maps API key
mode: driving (or walking, transit, etc.)
alternatives: true (to get multiple route options)
```

**Example Request:**
```
GET https://maps.googleapis.com/maps/api/directions/json?
  origin=21.1904,81.2849
  &destination=21.2000,81.3000
  &key=YOUR_API_KEY
  &mode=driving
  &alternatives=true
```

**Response Includes:**
- Route polylines (encoded and decoded)
- Distance and duration
- Turn-by-turn instructions
- Traffic information
- Route bounds

### Alternative APIs (Not Currently Used)

#### 1. **Google Maps Roads API**
- **Purpose**: Snap GPS points to roads
- **Use Case**: For snapping user's location to nearest road
- **Not for**: Getting routes between two points

#### 2. **Google Maps Distance Matrix API**
- **Purpose**: Calculate distance and duration between multiple origins and destinations
- **Use Case**: Batch distance calculations
- **Not for**: Getting detailed route paths

#### 3. **Google Maps Routes API (New)**
- **Purpose**: Advanced routing with more features
- **Note**: This is a newer API but Directions API is still the standard for route navigation

## Implementation Details

### Current Implementation:
1. **Route Fetching**: `DirectionsService.getRoutes()` method
2. **Route Display**: Polylines and polygons on the map
3. **Real-time Updates**: 
   - Automatic rerouting on deviation
   - Periodic updates every 30 seconds during navigation
   - Updates when location changes significantly

### Route Visualization:
- **Polylines**: Blue lines showing the route path
- **Polygons**: Semi-transparent blue area around the route (buffer zone)
- **Markers**: Start (current location) and end (drop location) points

### Performance Considerations:
- Routes are cached until user moves significantly
- API calls are debounced to avoid excessive requests
- Alternative routes are only fetched when explicitly requested
- Real-time updates are limited to navigation mode to save API quota

## Best Practices:

1. **API Key Security**: Never expose API key in client-side code (use backend proxy if possible)
2. **Rate Limiting**: Implement rate limiting to avoid exceeding quota
3. **Caching**: Cache routes for short periods to reduce API calls
4. **Error Handling**: Handle API errors gracefully (network issues, quota exceeded, etc.)
5. **Traffic Updates**: Update routes periodically during navigation for accurate ETAs

## Cost Considerations:

- **Directions API**: Pay-per-use based on requests
- **Free Tier**: $200/month credit (covers ~40,000 requests)
- **Optimization**: 
  - Only fetch routes when needed
  - Use alternatives=false when not needed
  - Cache routes appropriately
  - Limit real-time updates to navigation mode

