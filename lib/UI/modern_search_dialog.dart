import 'dart:async';
import 'package:flutter/material.dart';
import 'package:footttball/Services/api_service.dart';
import 'package:footttball/Helper/constants.dart';

class ModernSearchDialog extends StatefulWidget {
  final String nationality;
  final String club;

  const ModernSearchDialog({Key? key, required this.nationality, required this.club})
      : super(key: key);

  @override
  _ModernSearchDialogState createState() => _ModernSearchDialogState();
}

class _ModernSearchDialogState extends State<ModernSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.length >= 2) {
        _performSearch(query);
      } else {
        setState(() {
          _searchResults = [];
        });
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await ApiService().getPlayerNames(query: query);
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print("Search error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(16),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Constants().backgroundColor.withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Constants().darkBlue2,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Text(
                    "${widget.nationality} & ${widget.club}",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Search player...",
                      hintStyle: TextStyle(color: Colors.white70),
                      prefixIcon: Icon(Icons.search, color: Colors.white),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ],
              ),
            ),
            
            // Results List
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : _searchResults.isEmpty
                      ? Center(
                          child: Text(
                            "Type to search players...",
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final player = _searchResults[index];
                            return ListTile(
                              leading: ClipOval(
                                child: Image.network(
                                  player['image_url'] ?? '',
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      CircleAvatar(
                                    backgroundColor: Constants().lightGray,
                                    child: Text(
                                      player['name'][0].toUpperCase(),
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                player['name'],
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Constants().blackTextColor,
                                ),
                              ),
                              subtitle: Text(
                                "${player['position'] ?? ''} • ${player['country'] ?? player['nationality'] ?? ''}",
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                              trailing: Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.of(context).pop(player['name']);
                              },
                            );
                          },
                        ),
            ),
            
            // Close Button
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  "Cancel",
                  style: TextStyle(color: Constants().errorColor, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
