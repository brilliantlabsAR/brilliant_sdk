import 'dart:math';

class CompassHeading {
  // Basic heading calculation without tilt compensation
  static double calculateBasicHeading(double x, double y) {
    // Calculate the heading angle
    // Also rotate by -90 degrees in the XY plane because positive Y axis
    // points forward in the glasses, so that should have a heading of 0
    // when facing North
    final heading = atan2(y, x) - pi/2;

    // Convert to degrees
    var degrees = heading * 180 / pi;

    // Convert to 0-360 range
    if (degrees < 0) {
      degrees += 360;
    }

    return degrees;
  }

  // Tilt-compensated heading calculation
  static double calculateTiltCompensatedHeading({
    required double magX,
    required double magY,
    required double magZ,
    required double gravityX,
    required double gravityY,
    required double gravityZ,
    }) {
    //print('gX: ${gravityX.toStringAsFixed(2)}, gY: ${gravityY.toStringAsFixed(2)}, gZ: ${gravityZ.toStringAsFixed(2)}');

    double magDotGrav = magX * gravityX + magY * gravityY + magZ * gravityZ;
    //print('magX: ${magX.toStringAsFixed(2)}, magY: ${magY.toStringAsFixed(2)}, magZ: ${magZ.toStringAsFixed(2)}');

    // subtract out the component of the magnetic field parallel to the gravity vector
    double hMagX = magX - magDotGrav * gravityX;
    double hMagY = magY - magDotGrav * gravityY;
    //double hMagZ = magZ - magDotGrav * gravityZ;
    //print('hMagX: ${hMagX.toStringAsFixed(2)}, hMagY: ${hMagY.toStringAsFixed(2)}, dot: ${magDotGrav.toStringAsFixed(2)}');

    // Calculate the heading in radians (arctangent of Y / X)
    // Rotate our heading around because +Y should have a heading of 0, rather than +X
    double heading = atan2(hMagY, hMagX) - pi/2;

    // Convert to degrees
    var degrees = heading * 180 / pi;

    // Convert to 0-360 range
    if (degrees < 0) {
      degrees += 360;
    }

    return degrees;
  }

  // Convert heading to cardinal direction
  static String degreesToCardinal(double degrees) {
    const directions = [
      'N', 'NNE', 'NE', 'ENE',
      'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW',
      'W', 'WNW', 'NW', 'NNW'
    ];

    // Convert degrees to 16-point compass direction
    var index = ((degrees + 11.25) / 22.5).floor() % 16;
    return directions[index];
  }

  // Apply magnetic declination correction
  static double applyDeclination(double heading, double declination) {
    var correctedHeading = heading + declination;

    if (correctedHeading < 0) {
      correctedHeading += 360;
    } else if (correctedHeading > 360) {
      correctedHeading -= 360;
    }

    return correctedHeading;
  }
}