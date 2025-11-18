import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'nearby_places_service.dart';
import '../../../../core/constants/map_constants.dart';

/// AI-powered prediction for hyperlocal traffic and route optimization
class HyperlocalPrediction {
  final String prediction;
  final double confidence; // 0.0 to 1.0
  final String reasoning;
  final List<String> recommendations;
  final Map<String, dynamic> insights;

  HyperlocalPrediction({
    required this.prediction,
    required this.confidence,
    required this.reasoning,
    required this.recommendations,
    required this.insights,
  });
}

/// AI-powered route recommendation
class AIRouteRecommendation {
  final String recommendation;
  final String reasoning;
  final double timeSavings; // in minutes
  final List<String> benefits;
  final Map<String, dynamic> hyperlocalInsights;

  AIRouteRecommendation({
    required this.recommendation,
    required this.reasoning,
    required this.timeSavings,
    required this.benefits,
    required this.hyperlocalInsights,
  });
}

/// Hyperlocal business insights
class HyperlocalBusinessInsight {
  final String businessName;
  final String type;
  final LatLng location;
  final String peakHours;
  final String bestTimeToVisit;
  final double trafficImpact;
  final String localTip;

  HyperlocalBusinessInsight({
    required this.businessName,
    required this.type,
    required this.location,
    required this.peakHours,
    required this.bestTimeToVisit,
    required this.trafficImpact,
    required this.localTip,
  });
}

class GeminiAIService {
  static const String _geminiApiUrl = 'https://generativelanguage.googleapis.com/v1/models/gemini-1.5-flash:generateContent';
  
  String get _geminiApiKey => MapConstants.geminiApiKey;

  /// Get AI-powered traffic prediction for hyperlocal area
  Future<HyperlocalPrediction> predictTraffic({
    required LatLng location,
    required List<NearbyPlace> nearbyPlaces,
    required List<TrafficAlert> currentAlerts,
    DateTime? currentTime,
  }) async {
    final time = currentTime ?? DateTime.now();
    final hour = time.hour;
    final dayOfWeek = time.weekday; // 1 = Monday, 7 = Sunday
    
    try {
      // Build context for AI
      final context = _buildHyperlocalContext(
        location: location,
        nearbyPlaces: nearbyPlaces,
        currentAlerts: currentAlerts,
        hour: hour,
        dayOfWeek: dayOfWeek,
      );

      final prompt = '''
You are an AI assistant specialized in hyperlocal traffic prediction and route optimization for local communities.

Context:
$context

Based on this hyperlocal data, provide:
1. Traffic prediction for the next 1-2 hours
2. Confidence level (0-100%)
3. Reasoning based on local patterns
4. 3-5 specific recommendations for local residents
5. Insights about local businesses, markets, and peak times

Format your response as JSON:
{
  "prediction": "Brief traffic prediction",
  "confidence": 0.85,
  "reasoning": "Detailed reasoning",
  "recommendations": ["rec1", "rec2", "rec3"],
  "insights": {
    "peakHours": "8-10 AM, 5-7 PM",
    "bestTimeToVisit": "10 AM - 12 PM",
    "localEvents": "Market day on Sunday",
    "marketTimings": "6 AM - 8 PM"
  }
}
''';

      final response = await _callGeminiAPI(prompt);
      
      if (response != null) {
        return _parsePredictionResponse(response);
      }

      // Fallback prediction if AI fails
      return _generateFallbackPrediction(nearbyPlaces, currentAlerts, hour, dayOfWeek);
    } catch (e) {
      print('Error getting AI prediction: $e');
      return _generateFallbackPrediction(nearbyPlaces, currentAlerts, hour, dayOfWeek);
    }
  }

  /// Get AI-powered route recommendation for hyperlocal users
  Future<AIRouteRecommendation> recommendRoute({
    required LatLng origin,
    required LatLng destination,
    required List<NearbyPlace> originPlaces,
    required List<NearbyPlace> destinationPlaces,
    required List<TrafficAlert> alerts,
    DateTime? currentTime,
  }) async {
    try {
      final time = currentTime ?? DateTime.now();
      
      final prompt = '''
You are an AI assistant helping hyperlocal residents find the best routes considering:
- Local markets and vendors
- School timings
- Peak business hours
- Community events
- Local traffic patterns

Origin: ${origin.latitude}, ${origin.longitude}
Destination: ${destination.latitude}, ${destination.longitude}
Current Time: ${time.toString()}
Nearby Places at Origin: ${originPlaces.length}
Nearby Places at Destination: ${destinationPlaces.length}
Traffic Alerts: ${alerts.length}

Provide route recommendation in JSON:
{
  "recommendation": "Best route suggestion",
  "reasoning": "Why this route",
  "timeSavings": 5.0,
  "benefits": ["benefit1", "benefit2"],
  "hyperlocalInsights": {
    "avoidMarkets": true,
    "schoolTimings": "Avoid 8-9 AM, 3-4 PM",
    "vendorLocations": "Street vendors on Main St",
    "localTips": "Use back roads during market hours"
  }
}
''';

      final response = await _callGeminiAPI(prompt);
      
      if (response != null) {
        return _parseRouteRecommendation(response);
      }

      return _generateFallbackRouteRecommendation(alerts);
    } catch (e) {
      print('Error getting AI route recommendation: $e');
      return _generateFallbackRouteRecommendation(alerts);
    }
  }

  /// Get hyperlocal business insights
  Future<List<HyperlocalBusinessInsight>> getBusinessInsights({
    required List<NearbyPlace> places,
    DateTime? currentTime,
  }) async {
    final time = currentTime ?? DateTime.now();
    final hour = time.hour;
    
    try {
      final prompt = '''
Analyze these hyperlocal businesses and provide insights:

Places: ${places.map((p) => '${p.name} (${p.type})').join(', ')}

For each business, provide:
- Peak hours
- Best time to visit
- Traffic impact
- Local tips

Format as JSON array of insights.
''';

      final response = await _callGeminiAPI(prompt);
      
      if (response != null) {
        return _parseBusinessInsights(response, places);
      }

      return _generateFallbackBusinessInsights(places, hour);
    } catch (e) {
      print('Error getting business insights: $e');
      return _generateFallbackBusinessInsights(places, hour);
    }
  }

  /// Call Gemini API
  Future<String?> _callGeminiAPI(String prompt) async {
    try {
      // Check if API key is set
      final apiKey = _geminiApiKey;
      if (apiKey.isEmpty || apiKey == 'YOUR_GEMINI_API_KEY') {
        print('Gemini API key not configured. Using fallback predictions.');
        return null;
      }

      final url = Uri.parse('$_geminiApiUrl?key=$apiKey');
      
      final requestBody = json.encode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.7,
          'topK': 40,
          'topP': 0.95,
          'maxOutputTokens': 1024,
        }
      });

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: requestBody,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final candidates = data['candidates'] as List<dynamic>?;
        
        if (candidates != null && candidates.isNotEmpty) {
          final candidate = candidates[0] as Map<String, dynamic>;
          final content = candidate['content'] as Map<String, dynamic>;
          final parts = content['parts'] as List<dynamic>;
          
          if (parts.isNotEmpty) {
            final part = parts[0] as Map<String, dynamic>;
            return part['text'] as String?;
          }
        }
      } else {
        print('Gemini API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error calling Gemini API: $e');
    }
    
    return null;
  }

  /// Build hyperlocal context for AI
  String _buildHyperlocalContext({
    required LatLng location,
    required List<NearbyPlace> nearbyPlaces,
    required List<TrafficAlert> currentAlerts,
    required int hour,
    required int dayOfWeek,
  }) {
    final buffer = StringBuffer();
    
    buffer.writeln('Location: ${location.latitude}, ${location.longitude}');
    buffer.writeln('Current Time: ${hour}:00, Day: ${_getDayName(dayOfWeek)}');
    buffer.writeln('');
    buffer.writeln('Nearby Places (${nearbyPlaces.length}):');
    
    // Group by type
    final placesByType = <String, List<NearbyPlace>>{};
    for (final place in nearbyPlaces) {
      final type = place.type.toString();
      placesByType.putIfAbsent(type, () => []).add(place);
    }
    
    for (final entry in placesByType.entries) {
      buffer.writeln('  ${entry.key}: ${entry.value.length} places');
      for (final place in entry.value.take(3)) {
        buffer.writeln('    - ${place.name} (${place.distance.toStringAsFixed(0)}m away)');
      }
    }
    
    buffer.writeln('');
    buffer.writeln('Current Traffic Alerts (${currentAlerts.length}):');
    for (final alert in currentAlerts) {
      buffer.writeln('  - ${alert.message} (${alert.severityLevel})');
    }
    
    return buffer.toString();
  }

  String _getDayName(int dayOfWeek) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[dayOfWeek - 1];
  }

  /// Parse AI prediction response
  HyperlocalPrediction _parsePredictionResponse(String response) {
    try {
      // Try to extract JSON from response
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        final data = json.decode(jsonStr) as Map<String, dynamic>;
        
        return HyperlocalPrediction(
          prediction: data['prediction'] as String? ?? 'Moderate traffic expected',
          confidence: (data['confidence'] as num?)?.toDouble() ?? 0.7,
          reasoning: data['reasoning'] as String? ?? 'Based on local patterns',
          recommendations: (data['recommendations'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ?? [],
          insights: data['insights'] as Map<String, dynamic>? ?? {},
        );
      }
    } catch (e) {
      print('Error parsing AI response: $e');
    }
    
    // Fallback
    return HyperlocalPrediction(
      prediction: 'Traffic conditions normal',
      confidence: 0.6,
      reasoning: 'Unable to get AI prediction',
      recommendations: [],
      insights: {},
    );
  }

  /// Parse route recommendation
  AIRouteRecommendation _parseRouteRecommendation(String response) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        final data = json.decode(jsonStr) as Map<String, dynamic>;
        
        return AIRouteRecommendation(
          recommendation: data['recommendation'] as String? ?? 'Use recommended route',
          reasoning: data['reasoning'] as String? ?? 'Optimized for current conditions',
          timeSavings: (data['timeSavings'] as num?)?.toDouble() ?? 0.0,
          benefits: (data['benefits'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ?? [],
          hyperlocalInsights: data['hyperlocalInsights'] as Map<String, dynamic>? ?? {},
        );
      }
    } catch (e) {
      print('Error parsing route recommendation: $e');
    }
    
    return _generateFallbackRouteRecommendation([]);
  }

  /// Parse business insights
  List<HyperlocalBusinessInsight> _parseBusinessInsights(
    String response,
    List<NearbyPlace> places,
  ) {
    // Implementation would parse AI response
    // For now, return fallback
    return _generateFallbackBusinessInsights(places, DateTime.now().hour);
  }

  /// Generate fallback prediction when AI is unavailable
  HyperlocalPrediction _generateFallbackPrediction(
    List<NearbyPlace> places,
    List<TrafficAlert> alerts,
    int hour,
    int dayOfWeek,
  ) {
    // Analyze based on time and places
    String prediction = 'Moderate traffic expected';
    double confidence = 0.6;
    String reasoning = '';
    final recommendations = <String>[];
    
    // Peak hours analysis
    if (hour >= 7 && hour <= 9) {
      prediction = 'High traffic expected - Morning rush hour';
      confidence = 0.8;
      reasoning = 'Peak morning hours with schools and offices opening';
      recommendations.add('Leave 10-15 minutes earlier');
      recommendations.add('Avoid school zones if possible');
    } else if (hour >= 17 && hour <= 19) {
      prediction = 'High traffic expected - Evening rush hour';
      confidence = 0.8;
      reasoning = 'Evening peak hours with people returning home';
      recommendations.add('Consider alternative routes');
      recommendations.add('Check for local market closures');
    } else if (hour >= 10 && hour <= 14) {
      prediction = 'Moderate to low traffic';
      confidence = 0.7;
      reasoning = 'Off-peak hours, generally lighter traffic';
      recommendations.add('Good time for local shopping');
    }
    
    // Weekend analysis
    if (dayOfWeek == 6 || dayOfWeek == 7) {
      if (hour >= 10 && hour <= 16) {
        prediction = 'Moderate traffic - Weekend shopping hours';
        reasoning += ' Weekend market and shopping activity';
        recommendations.add('Markets may be busier on weekends');
      }
    }
    
    // Place-based analysis
    final marketCount = places.where((p) => 
      p.type == PlaceType.market || p.type == PlaceType.shoppingMall
    ).length;
    
    if (marketCount > 2) {
      reasoning += ' Multiple markets nearby may cause congestion';
      recommendations.add('Plan route to avoid market areas during peak hours');
    }
    
    final schoolCount = places.where((p) => 
      p.type == PlaceType.school || p.type == PlaceType.university
    ).length;
    
    if (schoolCount > 0 && (hour >= 7 && hour <= 9 || hour >= 14 && hour <= 16)) {
      reasoning += ' School timings may affect traffic';
      recommendations.add('Avoid school zones during drop-off/pick-up times');
    }
    
    return HyperlocalPrediction(
      prediction: prediction,
      confidence: confidence,
      reasoning: reasoning.isEmpty ? 'Based on local patterns' : reasoning,
      recommendations: recommendations.isEmpty 
          ? ['Check real-time traffic updates', 'Use alternative routes if available']
          : recommendations,
      insights: {
        'peakHours': '7-9 AM, 5-7 PM',
        'bestTimeToVisit': hour >= 10 && hour <= 14 ? 'Now' : '10 AM - 2 PM',
        'marketCount': marketCount,
        'schoolCount': schoolCount,
      },
    );
  }

  /// Generate fallback route recommendation
  AIRouteRecommendation _generateFallbackRouteRecommendation(
    List<TrafficAlert> alerts,
  ) {
    return AIRouteRecommendation(
      recommendation: 'Use optimized route avoiding high-traffic areas',
      reasoning: alerts.isNotEmpty 
          ? 'Route avoids ${alerts.length} high-traffic areas'
          : 'Route optimized for current conditions',
      timeSavings: alerts.length * 2.0, // Estimate 2 min per alert avoided
      benefits: [
        'Avoids traffic congestion',
        'Shorter travel time',
        'Better for local navigation',
      ],
      hyperlocalInsights: {
        'alertsAvoided': alerts.length,
        'localOptimization': true,
      },
    );
  }

  /// Generate fallback business insights
  List<HyperlocalBusinessInsight> _generateFallbackBusinessInsights(
    List<NearbyPlace> places,
    int currentHour,
  ) {
    return places.take(5).map((place) {
      String peakHours = '9 AM - 7 PM';
      String bestTime = '10 AM - 12 PM';
      
      if (place.type == PlaceType.school || place.type == PlaceType.university) {
        peakHours = '7-9 AM, 2-4 PM';
        bestTime = '10 AM - 2 PM';
      } else if (place.type == PlaceType.market) {
        peakHours = '6-10 AM, 5-8 PM';
        bestTime = '10 AM - 12 PM';
      } else if (place.type == PlaceType.cafe || place.type == PlaceType.restaurant) {
        peakHours = '8-10 AM, 12-2 PM, 6-9 PM';
        bestTime = '2-5 PM';
      }
      
      return HyperlocalBusinessInsight(
        businessName: place.name,
        type: place.type.toString(),
        location: place.location,
        peakHours: peakHours,
        bestTimeToVisit: bestTime,
        trafficImpact: place.trafficImpact,
        localTip: _generateLocalTip(place.type),
      );
    }).toList();
  }

  String _generateLocalTip(PlaceType type) {
    switch (type) {
      case PlaceType.market:
        return 'Best visited early morning or late evening to avoid crowds';
      case PlaceType.school:
      case PlaceType.university:
        return 'Avoid during 8-9 AM and 3-4 PM for lighter traffic';
      case PlaceType.cafe:
      case PlaceType.restaurant:
        return 'Peak hours are meal times, visit between meals';
      case PlaceType.shoppingMall:
      case PlaceType.mall:
        return 'Weekend afternoons are busiest, weekdays are quieter';
      default:
        return 'Check local timings for best visit time';
    }
  }
}